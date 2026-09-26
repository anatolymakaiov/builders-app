import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../models/chat_image_gallery.dart';
import '../../../screens/image_gallery_viewer_screen.dart';
import '../../services/web_chat_media_service.dart';
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

class WebChatAttachmentsView extends StatelessWidget {
  const WebChatAttachmentsView({
    super.key,
    required this.attachments,
    required this.isMine,
  });

  final List<WebChatAttachment> attachments;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < attachments.length; index++) ...[
          const SizedBox(height: 8),
          _AttachmentTile(
            attachment: attachments[index],
            attachments: attachments,
            index: index,
            isMine: isMine,
          ),
        ],
      ],
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
  });

  final WebChatAttachment attachment;
  final List<WebChatAttachment> attachments;
  final int index;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    if (ChatImageGallery.isPreviewableImage(attachment.toMap())) {
      return _ImageAttachment(
        attachment: attachment,
        attachments: attachments,
        index: index,
        isMine: isMine,
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
  });

  final WebChatAttachment attachment;
  final List<WebChatAttachment> attachments;
  final int index;
  final bool isMine;

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
      child: Container(
        width: 280,
        height: 190,
        decoration: BoxDecoration(
          border: Border.all(
            color: isMine
                ? WebTheme.accentBorder
                : WebChatMessageColors.incomingAttachment,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: WebRemoteImage(
            url: attachment.url,
            fit: BoxFit.cover,
          ),
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
  final player = AudioPlayer();
  bool playing = false;

  @override
  void initState() {
    super.initState();
    player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => playing = false);
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: _attachmentButtonStyle(widget.isMine),
      onPressed: () async {
        if (playing) {
          await player.pause();
        } else {
          await player.play(UrlSource(widget.attachment.url));
        }
        if (mounted) setState(() => playing = !playing);
      },
      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
      label: Text(widget.attachment.fileName),
    );
  }
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
