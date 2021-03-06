package io.spring.cloud.samples.brewery.common;

import com.google.common.collect.LinkedListMultimap;
import com.google.common.collect.Multimap;
import com.google.common.collect.Multimaps;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.cloud.sleuth.metric.SpanMetricReporter;
import org.springframework.cloud.sleuth.zipkin.HttpZipkinSpanReporter;
import org.springframework.cloud.sleuth.zipkin.ZipkinProperties;
import org.springframework.cloud.sleuth.zipkin.ZipkinSpanReporter;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import zipkin.Span;

import java.util.Collection;

/**
 * @author Marcin Grzejszczak
 */
@Component
@RestController
@Slf4j
public class StoringZipkinSpanReporter implements ZipkinSpanReporter {

	private final Multimap<Long, Span> sentSpans = Multimaps.synchronizedListMultimap(
			LinkedListMultimap.create());
	private final HttpZipkinSpanReporter delegate;

	@Autowired
	public StoringZipkinSpanReporter(SpanMetricReporter spanReporterService, ZipkinProperties zipkin) {
		delegate = new HttpZipkinSpanReporter(zipkin.getBaseUrl(), zipkin.getFlushInterval(),
				zipkin.getCompression().isEnabled(), spanReporterService);
	}

	@RequestMapping("/spans/{traceId}")
	public ResponseEntity<Collection<Span>> spans(@PathVariable String traceId) {
		Collection<Span> spansForTrace = sentSpans
				.get(org.springframework.cloud.sleuth.Span.hexToId(traceId));
		return ResponseEntity.ok(spansForTrace);
	}

	@Override
	public void report(Span span) {
		sentSpans.put(span.traceId, span);
		log.info("Sending span [" + span.toString() + "] to Zipkin");
		delegate.report(span);
	}
}
