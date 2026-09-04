import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Displays an untrusted catalog image without allowing an unbounded download.
///
/// This deliberately does not send cookies or API credentials, does not follow
/// redirects, and allows cleartext images only in debug builds used with a
/// local development API.
class BoundedNetworkImage extends StatefulWidget {
  const BoundedNetworkImage({
    super.key,
    required this.url,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.semanticLabel,
    this.timeout = const Duration(seconds: 10),
    this.maximumBytes = 5 * 1024 * 1024,
    @visibleForTesting this.clientFactory,
  });

  final String url;
  final Widget fallback;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final String? semanticLabel;
  final Duration timeout;
  final int maximumBytes;
  final http.Client Function()? clientFactory;

  @override
  State<BoundedNetworkImage> createState() => _BoundedNetworkImageState();
}

class _BoundedNetworkImageState extends State<BoundedNetworkImage> {
  Uint8List? _bytes;
  http.Client? _client;
  Completer<void>? _abortRequest;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant BoundedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.maximumBytes != widget.maximumBytes ||
        oldWidget.timeout != widget.timeout ||
        oldWidget.clientFactory != widget.clientFactory) {
      _cancelRequest();
      _bytes = null;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _cancelRequest();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return widget.fallback;
    return Image.memory(
      bytes,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      semanticLabel: widget.semanticLabel,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => widget.fallback,
    );
  }

  Future<void> _load() async {
    final uri = Uri.tryParse(widget.url.trim());
    if (!_isAllowedUri(uri) ||
        widget.maximumBytes < 1 ||
        widget.timeout <= Duration.zero) {
      return;
    }

    final generation = ++_generation;
    final client = widget.clientFactory?.call() ?? http.Client();
    final abortRequest = Completer<void>();
    _client = client;
    _abortRequest = abortRequest;
    final timer = Timer(widget.timeout, () {
      if (!abortRequest.isCompleted) abortRequest.complete();
    });

    try {
      final request =
          http.AbortableRequest('GET', uri!, abortTrigger: abortRequest.future)
            ..headers['Accept'] = 'image/*'
            ..followRedirects = false;
      final response = await client.send(request).timeout(widget.timeout);
      final contentType = response.headers['content-type']?.toLowerCase();
      if (response.statusCode != 200 ||
          (contentType != null &&
              !contentType.startsWith('image/') &&
              contentType != 'application/octet-stream')) {
        if (!abortRequest.isCompleted) abortRequest.complete();
        _showFallback(generation);
        return;
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (builder.length + chunk.length > widget.maximumBytes) {
          _showFallback(generation);
          return;
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty || !mounted || generation != _generation) return;
      setState(() => _bytes = bytes);
    } on Object {
      // A missing or unsafe catalog image falls back to the product icon. It
      // must never prevent barcode lookup, local pricing, or cart use.
      _showFallback(generation);
    } finally {
      timer.cancel();
      client.close();
      if (identical(_client, client)) _client = null;
      if (identical(_abortRequest, abortRequest)) _abortRequest = null;
    }
  }

  void _showFallback(int generation) {
    if (mounted && generation == _generation) {
      setState(() => _bytes = null);
    }
  }

  void _cancelRequest() {
    _generation++;
    final abortRequest = _abortRequest;
    if (abortRequest != null && !abortRequest.isCompleted) {
      abortRequest.complete();
    }
    _client?.close();
    _client = null;
    _abortRequest = null;
  }
}

bool _isAllowedUri(Uri? uri) =>
    uri != null &&
    uri.hasAuthority &&
    uri.userInfo.isEmpty &&
    (uri.scheme == 'https' || (kDebugMode && uri.scheme == 'http'));
