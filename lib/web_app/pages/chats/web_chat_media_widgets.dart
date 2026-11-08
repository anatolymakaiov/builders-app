import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../models/chat_image_gallery.dart';
import '../../../models/chat_media_gallery_layout.dart';
import '../../../screens/image_gallery_viewer_screen.dart';
import '../../services/web_chat_media_service.dart';
import '../../services/web_voice_playback_stub.dart'
    if (dart.library.js_interop) '../../services/web_voice_playback_browser.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_remote_image.dart';

class WebChatMessageColors {
  static const incoming = Color(0xFFE5F2EA);
  static const incomingInk = Color(0xFF18442E);
  static const incomingAttachment = Color(0xFF286D4E);
  static const outgoingAttachment = WebTheme.accentSoft;
}

class WebChatAttachMenu extends StatelessWidget {
  const WebChatAttachMenu({
    super.key,
    required this.enabled,
    required this.onSelected,
  });

  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'Attach',
      icon: const Icon(Icons.attach_file),
      position: PopupMenuPosition.over,
      style: IconButton.styleFrom(
        side: const BorderSide(color: WebTheme.borderStrong),
      ),
      onSelected: onSelected,
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'photo', child: Text('Photo')),
        PopupMenuItem(value: 'video', child: Text('Video')),
        PopupMenuItem(value: 'file', child: Text('File')),
      ],
    );
  }
}

class WebChatAttachmentsView extends StatefulWidget {
  const WebChatAttachmentsView({
    super.key,
    required this.attachments,
    required this.isMine,
    this.imageProviderFor,
    this.imagePreviewBuilder,
  });

  final List<WebChatAttachment> attachments;
  final bool isMine;
  final ImageProvider Function(String url)? imageProviderFor;
  final Widget Function(
          WebChatAttachment attachment, double width, double height)?
      imagePreviewBuilder;

  @override
  State<WebChatAttachmentsView> createState() => _WebChatAttachmentsViewState();
}

class _WebChatAttachmentsViewState extends State<WebChatAttachmentsView> {
  final Map<String, bool> landscape = {};
  final Map<String, (ImageStream, ImageStreamListener)> listeners = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveOrientations();
  }

  @override
  void didUpdateWidget(covariant WebChatAttachmentsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urls = widget.attachments.map((item) => item.url.trim()).toSet();
    landscape.removeWhere((url, _) => !urls.contains(url));
    for (final url in listeners.keys.toList()) {
      if (urls.contains(url)) continue;
      final (stream, listener) = listeners.remove(url)!;
      stream.removeListener(listener);
    }
    _resolveOrientations();
  }

  void _resolveOrientations() {
    for (final item in widget.attachments) {
      if (!ChatImageGallery.isPreviewableImage(item.toMap())) continue;
      final url = item.url.trim();
      if (url.isEmpty ||
          landscape.containsKey(url) ||
          listeners.containsKey(url)) {
        continue;
      }
      final provider = widget.imageProviderFor?.call(url) ??
          NetworkImage(url,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback);
      final stream = provider.resolve(
        createLocalImageConfiguration(context, size: const Size(280, 190)),
      );
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          stream.removeListener(listener);
          listeners.remove(url);
          final isLandscape = info.image.width > info.image.height;
          Future.microtask(() {
            if (!mounted ||
                !widget.attachments.any((item) => item.url.trim() == url)) {
              return;
            }
            setState(() => landscape[url] = isLandscape);
          });
        },
        onError: (_, __) {
          stream.removeListener(listener);
          listeners.remove(url);
        },
      );
      listeners[url] = (stream, listener);
      stream.addListener(listener);
    }
  }

  @override
  void dispose() {
    for (final (stream, listener) in listeners.values) {
      stream.removeListener(listener);
    }
    listeners.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.attachments.isEmpty) return const SizedBox.shrink();
    final kinds = [
      for (final item in widget.attachments)
        if (!ChatImageGallery.isPreviewableImage(item.toMap()))
          ChatMediaTileKind.other
        else if (landscape[item.url.trim()] == true)
          ChatMediaTileKind.landscape
        else
          ChatMediaTileKind.portrait,
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: LayoutBuilder(builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 280.0;
        final columns = width >= 330
            ? 3
            : width >= 220
                ? 2
                : 1;
        final rows = <List<int>>[];
        for (final row in ChatMediaGalleryLayout.rows(kinds)) {
          if (row.length == 1 ||
              kinds[row.first] != ChatMediaTileKind.portrait) {
            rows.add(row);
          } else {
            for (var start = 0; start < row.length; start += columns) {
              rows.add(row.skip(start).take(columns).toList());
            }
          }
        }
        const gap = 1.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              widget.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            for (var row = 0; row < rows.length; row++) ...[
              if (row > 0)
                SizedBox(
                    height: kinds[rows[row].first] == ChatMediaTileKind.other
                        ? 8
                        : gap),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var cell = 0; cell < rows[row].length; cell++) ...[
                    if (cell > 0) const SizedBox(width: gap),
                    _tile(
                        rows[row][cell],
                        kinds[rows[row][cell]],
                        (width - gap * (rows[row].length - 1)) /
                            rows[row].length),
                  ],
                ],
              ),
            ],
          ],
        );
      }),
    );
  }

  Widget _tile(int index, ChatMediaTileKind kind, double width) {
    final imageWidth =
        kind == ChatMediaTileKind.portrait && width > 280 ? 280.0 : width;
    final height = kind == ChatMediaTileKind.landscape
        ? imageWidth * 9 / 16
        : imageWidth * 4 / 3;
    return SizedBox(
      width: kind == ChatMediaTileKind.other ? width : imageWidth,
      child: _AttachmentTile(
        attachment: widget.attachments[index],
        attachments: widget.attachments,
        index: index,
        isMine: widget.isMine,
        imageWidth: imageWidth,
        imageHeight: height,
        imagePreviewBuilder: widget.imagePreviewBuilder,
      ),
    );
  }
}

class WebPendingAttachmentsPreview extends StatelessWidget {
  const WebPendingAttachmentsPreview({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  final List<WebPendingChatAttachment> attachments;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < attachments.length; i++)
            Chip(
              avatar: Icon(_iconForType(attachments[i].type), size: 18),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  attachments[i].fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              onDeleted: () => onRemove(i),
            ),
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.attachments,
    required this.index,
    required this.isMine,
    required this.imageWidth,
    required this.imageHeight,
    required this.imagePreviewBuilder,
  });

  final WebChatAttachment attachment;
  final List<WebChatAttachment> attachments;
  final int index;
  final bool isMine;
  final double imageWidth;
  final double imageHeight;
  final Widget Function(
          WebChatAttachment attachment, double width, double height)?
      imagePreviewBuilder;

  @override
  Widget build(BuildContext context) {
    if (ChatImageGallery.isPreviewableImage(attachment.toMap())) {
      return _ImageAttachment(
        attachment: attachment,
        attachments: attachments,
        index: index,
        isMine: isMine,
        width: imageWidth,
        height: imageHeight,
        previewBuilder: imagePreviewBuilder,
      );
    }
    switch (attachment.type) {
      case 'video':
        return _VideoAttachment(attachment: attachment, isMine: isMine);
      case 'audio':
        return _AudioAttachment(attachment: attachment, isMine: isMine);
      default:
        return _FileAttachment(attachment: attachment, isMine: isMine);
    }
  }
}

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({
    required this.attachment,
    required this.attachments,
    required this.index,
    required this.isMine,
    required this.width,
    required this.height,
    required this.previewBuilder,
  });

  final WebChatAttachment attachment;
  final List<WebChatAttachment> attachments;
  final int index;
  final bool isMine;
  final double width;
  final double height;
  final Widget Function(
          WebChatAttachment attachment, double width, double height)?
      previewBuilder;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final gallery = ChatImageGallery.fromAttachments(
          attachments.map((item) => item.toMap()).toList(growable: false),
          index,
        );
        if (gallery == null) return;
        showImageGallery(
          context,
          imageUrls: gallery.urls,
          initialIndex: gallery.initialIndex,
        );
      },
      child: SizedBox(
        width: width,
        height: height,
        child: previewBuilder?.call(attachment, width, height) ??
            WebRemoteImage(
              key: ValueKey('chat-image:${attachment.url}'),
              url: attachment.url,
              storagePath: attachment.storagePath,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              errorLabel: 'Image unavailable',
            ),
      ),
    );
  }
}

class _VideoAttachment extends StatefulWidget {
  const _VideoAttachment({required this.attachment, required this.isMine});

  final WebChatAttachment attachment;
  final bool isMine;

  @override
  State<_VideoAttachment> createState() => _VideoAttachmentState();
}

class _VideoAttachmentState extends State<_VideoAttachment> {
  VideoPlayerController? controller;
  Object? error;
  bool loading = false;

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (loading || controller != null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final video = VideoPlayerController.networkUrl(
        Uri.parse(widget.attachment.url),
      );
      await video.initialize();
      if (!mounted) {
        await video.dispose();
        return;
      }
      setState(() {
        controller = video;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = controller;
    if (error != null) {
      return _OpenAttachmentRow(
        attachment: widget.attachment,
        isMine: widget.isMine,
        icon: Icons.movie_outlined,
        subtitle: 'Video cannot be previewed here',
      );
    }
    if (video == null) {
      return _OpenAttachmentRow(
        attachment: widget.attachment,
        isMine: widget.isMine,
        icon: Icons.movie_outlined,
        subtitle: loading ? 'Loading video preview...' : 'Load video preview',
        onTap: loading ? null : _load,
        openExternally: false,
        trailing: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.isMine ? WebTheme.accent : Colors.white,
                ),
              )
            : const Icon(Icons.play_circle_outline, size: 20),
      );
    }
    return SizedBox(
      width: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: video.value.aspectRatio,
            child: VideoPlayer(video),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            style: _attachmentButtonStyle(widget.isMine),
            onPressed: () {
              setState(() {
                video.value.isPlaying ? video.pause() : video.play();
              });
            },
            icon: Icon(video.value.isPlaying ? Icons.pause : Icons.play_arrow),
            label: Text(widget.attachment.fileName),
          ),
        ],
      ),
    );
  }
}

class _AudioAttachment extends StatefulWidget {
  const _AudioAttachment({required this.attachment, required this.isMine});

  final WebChatAttachment attachment;
  final bool isMine;

  @override
  State<_AudioAttachment> createState() => _AudioAttachmentState();
}

class _AudioAttachmentState extends State<_AudioAttachment> {
  late WebVoicePlayback player = WebVoicePlayback(
    onChanged: () {
      if (mounted) setState(() {});
    },
  );

  @override
  void didUpdateWidget(covariant _AudioAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.url != widget.attachment.url) {
      player.dispose();
      player = WebVoicePlayback(onChanged: () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = player.duration;
    final progress = duration == null || duration.inMilliseconds == 0
        ? null
        : (player.position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0);
    return Container(
      width: 300,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: widget.isMine
            ? WebChatMessageColors.outgoingAttachment
            : WebChatMessageColors.incomingAttachment,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isMine
              ? WebTheme.accentBorder
              : WebChatMessageColors.incomingAttachment,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip:
                player.playing ? 'Pause voice message' : 'Play voice message',
            onPressed: player.loading
                ? null
                : () => player.toggle(widget.attachment.url),
            icon: player.loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(player.playing ? Icons.pause : Icons.play_arrow),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: widget.isMine ? WebTheme.deep : Colors.white,
                  ),
                ),
                if (player.error != null)
                  Text(player.error!,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isMine ? WebTheme.deep : Colors.white,
                      ))
                else ...[
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: progress,
                    color: widget.isMine ? WebTheme.accent : Colors.white,
                    backgroundColor:
                        widget.isMine ? WebTheme.border : Colors.white24,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_voiceTime(player.position)} / '
                    '${duration == null ? '--:--' : _voiceTime(duration)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.isMine ? WebTheme.deep : Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _voiceTime(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _FileAttachment extends StatelessWidget {
  const _FileAttachment({required this.attachment, required this.isMine});

  final WebChatAttachment attachment;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return _OpenAttachmentRow(
      attachment: attachment,
      isMine: isMine,
      icon: Icons.insert_drive_file_outlined,
      subtitle: attachment.mimeType ?? 'File attachment',
    );
  }
}

class _OpenAttachmentRow extends StatelessWidget {
  const _OpenAttachmentRow({
    required this.attachment,
    required this.isMine,
    required this.icon,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.openExternally = true,
  });

  final WebChatAttachment attachment;
  final bool isMine;
  final IconData icon;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool openExternally;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap ??
          (openExternally
              ? () => launchUrl(
                    Uri.parse(attachment.url),
                    mode: LaunchMode.externalApplication,
                  )
              : null),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMine
              ? WebChatMessageColors.outgoingAttachment
              : WebChatMessageColors.incomingAttachment,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMine
                ? WebTheme.accentBorder
                : WebChatMessageColors.incomingAttachment,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isMine ? WebTheme.accent : Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isMine ? WebTheme.deep : Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMine ? WebTheme.muted : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            IconTheme(
              data: IconThemeData(
                color: isMine ? WebTheme.accent : Colors.white,
              ),
              child: trailing ?? const Icon(Icons.open_in_new, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

ButtonStyle _attachmentButtonStyle(bool isMine) => OutlinedButton.styleFrom(
      backgroundColor: isMine
          ? WebChatMessageColors.outgoingAttachment
          : WebChatMessageColors.incomingAttachment,
      foregroundColor: isMine ? WebTheme.deep : Colors.white,
      side: BorderSide(
        color: isMine
            ? WebTheme.accentBorder
            : WebChatMessageColors.incomingAttachment,
      ),
    );

IconData _iconForType(String type) {
  switch (type) {
    case 'image':
      return Icons.image_outlined;
    case 'video':
      return Icons.movie_outlined;
    case 'audio':
      return Icons.mic_none_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}
