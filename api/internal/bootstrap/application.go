// Package bootstrap provides application dependency injection and wiring.
// It implements the Composition Root pattern for clean dependency management.
package bootstrap

import (
	"context"
	"fmt"
	"net/http"

	httptrace "gopkg.in/DataDog/dd-trace-go.v1/contrib/net/http"
	"gopkg.in/DataDog/dd-trace-go.v1/ddtrace/tracer"

	apihttp "github.com/rafaelcmd/internal-developer-platform/api/internal/adapters/inbound/http"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/adapters/outbound/cognito"
	sqsadapter "github.com/rafaelcmd/internal-developer-platform/api/internal/adapters/outbound/sqs"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/application/service"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/config"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/infrastructure"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/logger"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/server"
)

// Application holds all the application dependencies and provides access to them.
// It implements the Dependency Injection Container pattern.
type Application struct {
	Config *config.Config
	Logger logger.Logger

	// Infrastructure
	AWSClients     *infrastructure.AWSClients
	ParameterStore *infrastructure.ParameterStore

	// Runtime configuration (loaded from Parameter Store)
	ProvisionerQueueURL string
	CognitoClientID     string

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

	// Initialize logger
	app.Logger = logger.New(logger.Config{
		Level:  cfg.App.LogLevel,
		Format: "json",
	})

	app.Logger.Info("Initializing application",
		logger.F("environment", cfg.App.Environment),
		logger.F("service", cfg.App.ServiceName),
	)

	// Initialize tracing if enabled
	if cfg.App.EnableTracing {
		tracer.Start()
		app.Logger.Info("Datadog tracer initialized")
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
		AllowedOrigins: a.Config.App.AllowedOrigins,
	}
	router := apihttp.NewRouterWithConfig(
		a.ResourceHandler,
		a.HealthHandler,
		a.AuthHandler,
		a.SwaggerHandler,
		routerConfig,
	)

	// Wrap with Datadog tracing if enabled
	var handler http.Handler = router
	if a.Config.App.EnableTracing {
		mux := httptrace.NewServeMux(httptrace.WithServiceName(a.Config.App.ServiceName))

		// Handle routes with environment prefix (for local development)
		basePath := fmt.Sprintf("/%s/", a.Config.App.Environment)
		stripPath := fmt.Sprintf("/%s", a.Config.App.Environment)
		mux.Handle(basePath, http.StripPrefix(stripPath, router))

		// Handle routes without prefix (API Gateway HTTP API strips the stage prefix)
		mux.Handle("/", router)
		handler = mux
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

	// Stop tracer
	if a.Config.App.EnableTracing {
		tracer.Stop()
	}

	return nil
}
