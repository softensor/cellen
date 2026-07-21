import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_state.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class PhotoItem {
  final String id;
  final String url;
  final String? caption;
  final String? dateStr;

  const PhotoItem({
    required this.id,
    required this.url,
    this.caption,
    this.dateStr,
  });

  factory PhotoItem.fromJson(Map<String, dynamic> json) {
    return PhotoItem(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ??
          json['photo_url']?.toString() ??
          json['image']?.toString() ??
          '',
      caption: json['caption']?.toString(),
      dateStr: json['photo_date']?.toString() ??
          json['date']?.toString() ??
          json['created_at']?.toString(),
    );
  }

  String get fullUrl {
    if (url.startsWith('http')) return url;
    return '$kMediaBase$url';
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final photosProvider =
    FutureProvider.autoDispose<List<PhotoItem>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/photos') as List;
  return data
      .map((e) => PhotoItem.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});

  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(photosProvider);
    final auth = ref.read(authProvider);
    final canUpload = auth.isAdmin || auth.isTeacherRole;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Galeria de Fotos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(photosProvider),
          ),
        ],
      ),
      floatingActionButton: canUpload
          ? FloatingActionButton.extended(
              onPressed: _pickAndUploadPhoto,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Adicionar Foto'),
            )
          : null,
      body: photosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(photosProvider),
        ),
        data: (photos) {
          if (photos.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined,
                      size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Sem fotos na galeria',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Toque no botão + para adicionar fotos',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(photosProvider),
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: photos.length,
              itemBuilder: (context, i) {
                return _PhotoCard(
                  photo: photos[i],
                  onTap: () => _openFullScreen(context, photos, i),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _openFullScreen(
      BuildContext context, List<PhotoItem> photos, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenGallery(
          photos: photos,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (xFile == null) return;

    // Read bytes upfront — Image.file is not supported on Flutter Web
    final imageBytes = await xFile.readAsBytes();

    // Show caption dialog
    if (!mounted) return;
    final captionCtrl = TextEditingController();
    DateTime? selectedDate;

    final confirmed = await showDialog<bool>(useRootNavigator: false, 
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Adicionar Foto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Preview
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    imageBytes,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 150,
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: Icon(Icons.image, size: 48, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: captionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Legenda (opcional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.text_fields),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    selectedDate != null
                        ? DateFormat('dd/MM/yyyy').format(selectedDate!)
                        : 'Data (hoje por omissão)',
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Carregar'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    // Upload with progress indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('A carregar foto...'),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      final api = ref.read(apiClientProvider);
      final bytes = await xFile.readAsBytes();
      final mimeType = xFile.mimeType ?? _mimeFromName(xFile.name);

      final formData = {
        'file': MultipartFile.fromBytes(
          bytes,
          filename: xFile.name,
          contentType: DioMediaType.parse(mimeType),
        ),
        if (captionCtrl.text.trim().isNotEmpty)
          'caption': captionCtrl.text.trim(),
        if (selectedDate != null)
          'photo_date': DateFormat('yyyy-MM-dd').format(selectedDate!),
      };

      await api.postForm('/photos', data: formData);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto adicionada com sucesso')),
        );
      }
      ref.invalidate(photosProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar foto: $e')),
        );
      }
    }
  }

  static String _mimeFromName(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _PhotoCard extends StatelessWidget {
  final PhotoItem photo;
  final VoidCallback onTap;

  const _PhotoCard({required this.photo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    String? formattedDate;
    if (photo.dateStr != null && photo.dateStr!.isNotEmpty) {
      final parsed = DateTime.tryParse(photo.dateStr!);
      if (parsed != null) {
        formattedDate = DateFormat('dd/MM/yy').format(parsed);
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: photo.fullUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: Colors.grey.shade200,
                child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              errorWidget: (_, __, ___) => Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image,
                    color: Colors.grey, size: 40),
              ),
            ),
            // Date stamp top-right
            if (formattedDate != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    formattedDate,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            // Caption overlay bottom
            if (photo.caption != null && photo.caption!.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    photo.caption!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenGallery extends StatefulWidget {
  final List<PhotoItem> photos;
  final int initialIndex;

  const _FullScreenGallery({
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_currentIndex];
    String? formattedDate;
    if (photo.dateStr != null) {
      final parsed = DateTime.tryParse(photo.dateStr!);
      if (parsed != null) {
        formattedDate =
            DateFormat('d \'de\' MMMM yyyy', 'pt_PT').format(parsed);
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.photos.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (context, i) {
                return InteractiveViewer(
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: widget.photos[i].fullUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator()),
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                          size: 64),
                    ),
                  ),
                );
              },
            ),
          ),
          if (photo.caption != null || formattedDate != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (photo.caption != null && photo.caption!.isNotEmpty)
                    Text(
                      photo.caption!,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16),
                    ),
                  if (formattedDate != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      formattedDate,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
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

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
