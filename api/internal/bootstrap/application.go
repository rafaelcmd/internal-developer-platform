// Package bootstrap provides application dependency injection and wiring.
// It implements the Composition Root pattern for clean dependency management.
package bootstrap

import (
	"context"
	"fmt"
	"net/http"

	"github.com/redis/go-redis/v9"
	"github.com/sirupsen/logrus"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	apihttp "github.com/rafaelcmd/internal-developer-platform/api/internal/adapters/inbound/http"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/adapters/outbound/cognito"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/adapters/outbound/idempotency"
	sqsadapter "github.com/rafaelcmd/internal-developer-platform/api/internal/adapters/outbound/sqs"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/application/service"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/config"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/ports/outbound"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/infrastructure"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/logger"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/server"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/telemetry"
)

// Application holds all the application dependencies and provides access to them.
// It implements the Dependency Injection Container pattern.
type Application struct {
	Config *config.Config
	Logger logger.Logger

	// Infrastructure
	AWSClients     *infrastructure.AWSClients
	ParameterStore *infrastructure.ParameterStore

	// Observability
	Metrics *telemetry.Metrics
	Tracing *telemetry.Tracing
	Logs    *telemetry.Logs

	// Runtime configuration (loaded from Parameter Store)
	ProvisionerQueueURL string
	CognitoClientID     string
	RedisAddr           string

	// Idempotency layer
	RedisClient      *redis.Client
	IdempotencyStore outbound.IdempotencyStore

	// Services
	ResourceService *service.ResourceService
	AuthService     *service.AuthService

	// HTTP Handlers
	ResourceHandler *apihttp.ResourceHandler
	AuthHandler     *apihttp.AuthHandler
	HealthHandler   *apihttp.HealthHandler
	SwaggerHandler  *apihttp.SwaggerHandler

	// Server
	Server *server.Server
}

// Options holds optional configuration for the Application.
type Options struct {
	SwaggerPath string
}

// DefaultOptions returns the default Application options.
func DefaultOptions() Options {
	return Options{
		SwaggerPath: "./docs/swagger.yaml",
	}
}

// New creates and initializes a new Application with all dependencies wired.
// This is the Composition Root - all dependency wiring happens here.
func New(ctx context.Context, cfg *config.Config, opts Options) (*Application, error) {
	app := &Application{
		Config: cfg,
	}

	// OTLP telemetry export (logs + traces) is enabled outside local mode, where
	// there is no Collector to receive it. Set up the logs pipeline before the
	// logger so its OTLP bridge hook can be attached at construction.
	otlpEnabled := cfg.App.EnableTracing && !app.isLocalMode()

	logCfg := logger.Config{Level: cfg.App.LogLevel, Format: "json"}
	if otlpEnabled {
		logs, err := telemetry.NewLogs(ctx, telemetry.LogsConfig{
			ServiceName:    cfg.App.ServiceName,
			ServiceVersion: cfg.App.Version,
			Environment:    cfg.App.Environment,
		})
		if err != nil {
			return nil, fmt.Errorf("failed to initialize logs pipeline: %w", err)
		}
		app.Logs = logs
		logCfg.Hooks = []logrus.Hook{logs.Hook()}
	}

	// Initialize logger
	app.Logger = logger.New(logCfg)

	app.Logger.Info("Initializing application",
		logger.F("environment", cfg.App.Environment),
		logger.F("service", cfg.App.ServiceName),
	)

	// Initialize distributed tracing (OTLP -> Collector; skipped in local mode)
	if otlpEnabled {
		tracing, err := telemetry.NewTracing(ctx, telemetry.TracingConfig{
			ServiceName:    cfg.App.ServiceName,
			ServiceVersion: cfg.App.Version,
			Environment:    cfg.App.Environment,
		})
		if err != nil {
			return nil, fmt.Errorf("failed to initialize tracing: %w", err)
		}
		app.Tracing = tracing
		app.Logger.Info("OpenTelemetry tracing initialized (OTLP exporter)")
	}

	// Initialize the OpenTelemetry metrics provider (Prometheus exporter)
	if err := app.initializeMetrics(); err != nil {
		return nil, fmt.Errorf("failed to initialize metrics: %w", err)
	}

	// In local mode, skip all AWS-backed wiring (Parameter Store, SQS, Cognito,
	// Redis) so the service boots for local testing of infra-free endpoints such
	// as /metrics and /v1/health. See initializeLocal for the caveats.
	if app.isLocalMode() {
		return app.initializeLocal(opts)
	}

	// Initialize AWS clients
	awsClients, err := infrastructure.NewAWSClients(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize AWS clients: %w", err)
	}
	app.AWSClients = awsClients
	app.ParameterStore = infrastructure.NewParameterStore(awsClients.SSM)

	// Load runtime configuration from Parameter Store
	if err := app.loadRuntimeConfig(ctx); err != nil {
		return nil, fmt.Errorf("failed to load runtime configuration: %w", err)
	}

	// Initialize Redis (idempotency backend)
	if err := app.initializeRedis(ctx); err != nil {
		return nil, fmt.Errorf("failed to initialize Redis: %w", err)
	}

	// Initialize adapters
	app.initializeAdapters(opts)

	// Initialize services
	app.initializeServices()

	// Initialize HTTP handlers
	app.initializeHandlers()

	// Initialize HTTP server
	if err := app.initializeServer(); err != nil {
		return nil, fmt.Errorf("failed to initialize server: %w", err)
	}

	app.Logger.Info("Application initialized successfully")
	return app, nil
}

// loadRuntimeConfig loads configuration from AWS Parameter Store.
func (a *Application) loadRuntimeConfig(ctx context.Context) error {
	var err error

	// Load SQS queue URL
	a.ProvisionerQueueURL, err = a.ParameterStore.GetParameter(ctx, a.Config.AWS.ProvisionerQueueParamKey)
	if err != nil {
		return fmt.Errorf("failed to get provisioner queue URL: %w", err)
	}
	a.Logger.Info("Loaded provisioner queue URL", logger.F("queue_url", a.ProvisionerQueueURL))

	// Load Cognito Client ID
	a.CognitoClientID, err = a.ParameterStore.GetParameter(ctx, a.Config.AWS.CognitoClientIDParamKey)
	if err != nil {
		return fmt.Errorf("failed to get Cognito client ID: %w", err)
	}
	a.Logger.Info("Loaded Cognito client ID", logger.F("client_id", a.CognitoClientID))

	// REDIS_ADDR (env override) wins for local docker-compose; otherwise pull from Parameter Store
	// where Terraform writes the ElastiCache primary endpoint.
	if a.Config.Idempotency.RedisAddr != "" {
		a.RedisAddr = a.Config.Idempotency.RedisAddr
	} else if a.Config.AWS.RedisAddrParamKey != "" {
		a.RedisAddr, err = a.ParameterStore.GetParameter(ctx, a.Config.AWS.RedisAddrParamKey)
		if err != nil {
			return fmt.Errorf("failed to get Redis address: %w", err)
		}
	}
	if a.RedisAddr != "" {
		a.Logger.Info("Loaded Redis address", logger.F("redis_addr", a.RedisAddr))
	}

	return nil
}

// initializeRedis dials Redis and constructs the idempotency store. The store is left
// nil when no address is configured, which causes the router to skip the middleware —
// useful for environments that haven't provisioned Redis yet.
func (a *Application) initializeRedis(ctx context.Context) error {
	if a.RedisAddr == "" {
		a.Logger.Warn("Redis address not configured; idempotency layer disabled")
		return nil
	}

	client, err := infrastructure.NewRedisClient(ctx, infrastructure.RedisConfig{
		Addr:         a.RedisAddr,
		Password:     a.Config.Idempotency.RedisPassword,
		DB:           a.Config.Idempotency.RedisDB,
		DialTimeout:  a.Config.Idempotency.DialTimeout,
		ReadTimeout:  a.Config.Idempotency.ReadTimeout,
		WriteTimeout: a.Config.Idempotency.WriteTimeout,
	})
	if err != nil {
		return err
	}

	a.RedisClient = client
	a.IdempotencyStore = idempotency.NewRedisStore(client)
	a.Logger.Info("Idempotency layer enabled (redis)")
	return nil
}

// isLocalMode reports whether the app is running in local development mode,
// where AWS-backed dependencies are disabled.
func (a *Application) isLocalMode() bool {
	return a.Config.App.Environment == "local"
}

// initializeLocal wires the minimal set of dependencies that need no external
// infrastructure, for local development. AWS clients, Parameter Store, SQS,
// Cognito, and Redis are all skipped, so only infra-free endpoints (/metrics,
// /v1/health, and swagger) are functional — the resource and auth routes are
// registered but will return 500 (recovered) if called, since their services
// are nil.
func (a *Application) initializeLocal(opts Options) (*Application, error) {
	a.Logger.Warn("Running in LOCAL mode: AWS, Parameter Store, and Redis are disabled",
		logger.F("functional_endpoints", "/metrics, /v1/health, /v1/swagger"),
	)

	a.initializeAdapters(opts)
	a.initializeHandlers()

	if err := a.initializeServer(); err != nil {
		return nil, fmt.Errorf("failed to initialize server: %w", err)
	}

	a.Logger.Info("Application initialized successfully (local mode)")
	return a, nil
}

// initializeMetrics constructs the OpenTelemetry MeterProvider backed by the
// Prometheus exporter and registers it as the global provider.
func (a *Application) initializeMetrics() error {
	metrics, err := telemetry.NewMetrics(telemetry.MetricsConfig{
		ServiceName:    a.Config.App.ServiceName,
		ServiceVersion: a.Config.App.Version,
		Environment:    a.Config.App.Environment,
	})
	if err != nil {
		return err
	}

	a.Metrics = metrics
	a.Logger.Info("OpenTelemetry metrics provider initialized (prometheus exporter)")
	return nil
}

// initializeAdapters initializes all outbound adapters.
func (a *Application) initializeAdapters(opts Options) {
	a.SwaggerHandler = apihttp.NewSwaggerHandler(opts.SwaggerPath)
}

// initializeServices initializes all application services.
func (a *Application) initializeServices() {
	// Resource service with SQS publisher
	resourcePublisher := sqsadapter.NewResourcePublisher(a.AWSClients.SQS, a.ProvisionerQueueURL)
	a.ResourceService = service.NewResourceService(resourcePublisher)

	// Auth service with Cognito provider
	authProvider := cognito.NewCognitoAuthProvider(a.AWSClients.Cognito, a.CognitoClientID)
	a.AuthService = service.NewAuthService(authProvider)
}

// initializeHandlers initializes all HTTP handlers.
func (a *Application) initializeHandlers() {
	a.ResourceHandler = apihttp.NewResourceHandler(a.ResourceService)
	a.AuthHandler = apihttp.NewAuthHandler(a.AuthService, a.Logger)
	a.HealthHandler = apihttp.NewHealthHandler()
}

// initializeServer initializes the HTTP server with routing and middleware.
func (a *Application) initializeServer() error {
	// Create router with all handlers
	routerConfig := apihttp.RouterConfig{
		AllowedOrigins:   a.Config.App.AllowedOrigins,
		IdempotencyStore: a.IdempotencyStore,
		IdempotencyTTL:   a.Config.Idempotency.TTL,
		MetricsHandler:   a.Metrics.Handler(),
	}
	router := apihttp.NewRouterWithConfig(
		a.ResourceHandler,
		a.HealthHandler,
		a.AuthHandler,
		a.SwaggerHandler,
		routerConfig,
	)

	// Wrap with OpenTelemetry HTTP instrumentation if enabled (skipped in local
	// mode). otelhttp starts a server span per request from the propagated
	// context and hands spans to the global TracerProvider (OTLP -> Collector).
	var handler http.Handler = router
	if a.Config.App.EnableTracing && !a.isLocalMode() {
		mux := http.NewServeMux()

		// Handle routes with environment prefix (for local development)
		basePath := fmt.Sprintf("/%s/", a.Config.App.Environment)
		stripPath := fmt.Sprintf("/%s", a.Config.App.Environment)
		mux.Handle(basePath, http.StripPrefix(stripPath, router))

		// Handle routes without prefix (API Gateway HTTP API strips the stage prefix)
		mux.Handle("/", router)

		handler = otelhttp.NewHandler(mux, "http.server")
	}

	// Create server
	serverConfig := server.Config{
		Port:            a.Config.Server.Port,
		ReadTimeout:     a.Config.Server.ReadTimeout,
		WriteTimeout:    a.Config.Server.WriteTimeout,
		IdleTimeout:     a.Config.Server.IdleTimeout,
		ShutdownTimeout: a.Config.Server.ShutdownTimeout,
	}
	a.Server = server.New(handler, serverConfig, a.Logger)

	return nil
}

// Run starts the application and blocks until shutdown.
func (a *Application) Run(ctx context.Context) error {
	a.Logger.Info("Starting application",
		logger.F("port", a.Config.Server.Port),
		logger.F("environment", a.Config.App.Environment),
	)
	return a.Server.Start(ctx)
}

// Shutdown gracefully shuts down the application.
func (a *Application) Shutdown() error {
	a.Logger.Info("Shutting down application")

	if a.RedisClient != nil {
		if err := a.RedisClient.Close(); err != nil {
			a.Logger.Warn("Failed to close Redis client", logger.F("error", err.Error()))
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), a.Config.Server.ShutdownTimeout)
	defer cancel()

	// Flush and release the telemetry providers (metrics, traces, logs). Logs is
	// shut down last so the preceding shutdown steps can still be logged.
	if a.Metrics != nil {
		if err := a.Metrics.Shutdown(ctx); err != nil {
			a.Logger.Warn("Failed to shut down metrics provider", logger.F("error", err.Error()))
		}
	}
	if a.Tracing != nil {
		if err := a.Tracing.Shutdown(ctx); err != nil {
			a.Logger.Warn("Failed to shut down tracing provider", logger.F("error", err.Error()))
		}
	}
	if a.Logs != nil {
		if err := a.Logs.Shutdown(ctx); err != nil {
			a.Logger.Warn("Failed to shut down logs provider", logger.F("error", err.Error()))
		}
	}

	return nil
}
