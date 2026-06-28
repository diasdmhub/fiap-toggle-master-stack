package main

import (
	"context"
	"log"
	"os"
	"strings"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

const defaultOTLPEndpoint = "otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317"

// tracer é usado por evaluator.go, sqs.go e handlers.go para criar spans manuais.
var tracer = otel.Tracer("evaluation-service")

// setupOTel inicializa TracerProvider e MeterProvider com exportadores OTLP/gRPC
// compartilhando a mesma conexão. O MeterProvider é necessário para que o
// otelhttp emita http.server.duration automaticamente.
func setupOTel(ctx context.Context, serviceName string) (func(context.Context) error, error) {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = defaultOTLPEndpoint
	}
	endpoint = strings.TrimPrefix(strings.TrimPrefix(endpoint, "https://"), "http://")

	conn, err := grpc.NewClient(endpoint, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, err
	}

	// --- Resource (atributos comuns a traces e métricas) ---
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
			semconv.ServiceNamespace("toggle"),
		),
		resource.WithFromEnv(),
		resource.WithHost(),
		resource.WithContainer(),
	)
	if err != nil {
		return nil, err
	}

	// --- TracerProvider ---
	traceExporter, err := otlptracegrpc.New(ctx, otlptracegrpc.WithGRPCConn(conn))
	if err != nil {
		return nil, err
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)

	// --- MeterProvider ---
	metricExporter, err := otlpmetricgrpc.New(ctx, otlpmetricgrpc.WithGRPCConn(conn))
	if err != nil {
		return nil, err
	}
	mp := metric.NewMeterProvider(
		metric.WithReader(metric.NewPeriodicReader(metricExporter)),
		metric.WithResource(res),
	)
	otel.SetMeterProvider(mp)

	// --- Propagador W3C ---
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	log.Printf("OpenTelemetry inicializado (service=%s, endpoint=%s)", serviceName, endpoint)

	return func(ctx context.Context) error {
		if err := mp.Shutdown(ctx); err != nil {
			log.Printf("Erro ao encerrar MeterProvider: %v", err)
		}
		return tp.Shutdown(ctx)
	}, nil
}