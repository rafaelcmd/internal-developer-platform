package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	"github.com/sirupsen/logrus"
	"go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-sdk-go-v2/otelaws"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/trace"

	"github.com/rafaelcmd/internal-developer-platform/resource-provisioner-service/internal/consumer"
	"github.com/rafaelcmd/internal-developer-platform/resource-provisioner-service/internal/logger"
	"github.com/rafaelcmd/internal-developer-platform/resource-provisioner-service/internal/telemetry"
)

const serviceName = "resource-provisioner-consumer"

var errEmptyQueueURL = errors.New("SQS queue URL is empty")

func main() {
	// Root context cancels on SIGINT/SIGTERM so the consumer drains and the
	// telemetry batch exporters flush before exit.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	shutdownTelemetry, logHook, err := telemetry.Setup(ctx, telemetry.Config{
		ServiceName: serviceName,
		Version:     os.Getenv("SERVICE_VERSION"),
		Environment: envOrDefault("ENVIRONMENT", "dev"),
	})

	// Build the logger after Setup so the OTLP bridge hook can be attached at
	// construction. logrus writes JSON to stdout unconditionally (local dev
	// visibility + host stdout archive); the hook mirrors every entry onto the
	// OTLP log pipeline for the vendor-agnostic Collector seam. In local Kafka
	// dev there is no Collector, so Setup returns a nil hook and logs just print.
	logCfg := logger.DefaultConfig()
	if logHook != nil {
		logCfg.Hooks = []logrus.Hook{logHook}
	}
	log := logger.New(logCfg)

	if err != nil {
		log.WithContext(ctx).Error("unable to set up telemetry", logger.F("error", err.Error()))
		os.Exit(1)
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdownTelemetry(shutdownCtx); err != nil {
			log.WithContext(shutdownCtx).Error("telemetry shutdown error", logger.F("error", err.Error()))
		}
	}()

	tracer := otel.Tracer(serviceName)
	metrics := consumer.NewMetrics(otel.Meter(serviceName))

	// Kafka is the local-dev transport: when brokers are configured we consume
	// from Kafka and never touch AWS. Otherwise fall back to SQS.
	if brokers := splitBrokers(os.Getenv("KAFKA_BROKERS")); len(brokers) > 0 {
		cfg := consumer.KafkaConfig{
			Brokers: brokers,
			Topic:   envOrDefault("KAFKA_TOPIC", "resource-provisioning"),
			GroupID: envOrDefault("KAFKA_GROUP_ID", "resource-provisioner"),
		}
		if err := consumer.RunKafka(ctx, cfg, tracer, metrics, log); err != nil && ctx.Err() == nil {
			log.WithContext(ctx).Error("kafka consumer error", logger.F("error", err.Error()))
			os.Exit(1)
		}
		return
	}

	if err := runSQS(ctx, tracer, metrics, log); err != nil && ctx.Err() == nil {
		log.WithContext(ctx).Error("sqs consumer error", logger.F("error", err.Error()))
		os.Exit(1)
	}
}

// runSQS loads AWS config, resolves the queue URL from Parameter Store, and
// consumes from SQS. Isolated from the Kafka path so local dev needs no AWS.
func runSQS(ctx context.Context, tracer trace.Tracer, metrics consumer.Metrics, log logger.Logger) error {
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion("us-east-1"))
	if err != nil {
		return fmt.Errorf("load AWS config: %w", err)
	}
	// Instrument every AWS SDK call with an OTel span (replaces xray.Client).
	otelaws.AppendMiddlewares(&cfg.APIOptions)

	ssmClient := ssm.NewFromConfig(cfg)
	sqsClient := sqs.NewFromConfig(cfg)

	queueURL, err := getQueueURL(ctx, tracer, ssmClient)
	if err != nil {
		return err
	}
	return consumer.RunSQS(ctx, sqsClient, queueURL, tracer, metrics, log)
}

// getQueueURL reads the provisioning queue URL from Parameter Store within its
// own span.
func getQueueURL(ctx context.Context, tracer trace.Tracer, ssmClient *ssm.Client) (string, error) {
	ctx, span := tracer.Start(ctx, "GetSQSQueueURL")
	defer span.End()

	param, err := ssmClient.GetParameter(ctx, &ssm.GetParameterInput{
		Name: aws.String("/INTERNAL_DEVELOPER_PLATFORM/SQS_QUEUE_URL"),
	})
	if err != nil {
		span.RecordError(err)
		return "", err
	}

	queueURL := aws.ToString(param.Parameter.Value)
	if queueURL == "" {
		return "", errEmptyQueueURL
	}
	return queueURL, nil
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// splitBrokers parses a comma-separated broker list, trimming blanks.
func splitBrokers(csv string) []string {
	var brokers []string
	for _, b := range strings.Split(csv, ",") {
		if b = strings.TrimSpace(b); b != "" {
			brokers = append(brokers, b)
		}
	}
	return brokers
}
