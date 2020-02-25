# frozen_string_literal: true

module PrometheusExporter::Server
  class WebCollector < TypeCollector
    DURATION_BUCKETS = [
        90,
        60,
        45,
        30,
        15,
        10,
        5,
        2.5,
        1,
        0.5,
        0.25,
        0.1,
        0.05,
        0.025,
        0.01,
        0.005
    ].freeze

    def initialize
      @metrics = {}
    end

    def type
      "web"
    end

    def collect(obj)
      ensure_metrics
      observe(obj)
    end

    def metrics
      @metrics.values
    end

    protected

    def ensure_metrics
      unless @http_requests_total
        @metrics["http_requests_total"] = @http_requests_total = PrometheusExporter::Metric::Counter.new(
          "http_requests_total",
          "Total HTTP requests from web app."
        )

        @metrics["http_duration_seconds"] = @http_duration_seconds = PrometheusExporter::Metric::Histogram.new(
          "http_duration_seconds",
          "Time spent in HTTP reqs in seconds.",
          buckets: DURATION_BUCKETS
        )

        @metrics["http_redis_duration_seconds"] = @http_redis_duration_seconds = PrometheusExporter::Metric::Histogram.new(
          "http_redis_duration_seconds",
          "Time spent in HTTP reqs in Redis, in seconds.",
          buckets: DURATION_BUCKETS
        )

        @metrics["http_sql_duration_seconds"] = @http_sql_duration_seconds = PrometheusExporter::Metric::Histogram.new(
          "http_sql_duration_seconds",
          "Time spent in HTTP reqs in SQL in seconds.",
          buckets: DURATION_BUCKETS
        )

        @metrics["http_queue_duration_seconds"] = @http_queue_duration_seconds = PrometheusExporter::Metric::Histogram.new(
          "http_queue_duration_seconds",
          "Time spent queueing the request in load balancer in seconds.",
          buckets: DURATION_BUCKETS
        )
      end
    end

    def observe(obj)
      default_labels = {
        controller: obj['controller'] || 'other',
        action: obj['action'] || 'other'
      }
      custom_labels = obj['custom_labels']
      labels = custom_labels.nil? ? default_labels : default_labels.merge(custom_labels)

      @http_requests_total.observe(1, labels.merge(status: obj["status"]))

      if timings = obj["timings"]
        @http_duration_seconds.observe(timings["total_duration"], labels)
        if redis = timings["redis"]
          @http_redis_duration_seconds.observe(redis["duration"], labels)
        end
        if sql = timings["sql"]
          @http_sql_duration_seconds.observe(sql["duration"], labels)
        end
      end
      if queue_time = obj["queue_time"]
        @http_queue_duration_seconds.observe(queue_time, labels)
      end
    end
  end
end
