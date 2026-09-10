import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/attachment_upload_service.dart';
import '../services/smiley_service.dart';

/// 回复输入（顶楼回帖 / 楼中楼回复）共用的表情选择与图片上传工具。
///
/// - 表情: 从论坛拉取表情列表, 选择一个返回可插入正文的 `:code:`。
/// - 图片: 用当前登录态上传到论坛, 成功后返回可插入正文的 `[attachimg]aid[/attachimg]`。
class ForumReplyTools {
  ForumReplyTools._();

  /// 弹出表情选择面板, 返回用户选中的表情 BBCode(形如 `:lol:`), 取消返回 null。
  static Future<String?> pickSmiley(BuildContext context, int fid) async {
    final smileys = await SmileyService.instance.fetchSmileys(fid);
    if (!context.mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text('表情', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    alignment: WrapAlignment.start,
                    spacing: 6,
                    runSpacing: 6,
                    children: smileys.isEmpty
                        ? const [Padding(padding: EdgeInsets.all(8), child: Text('暂未获取到表情'))]
                        : smileys.map((s) {
                            return SizedBox(
                              width: 48,
                              height: 48,
                              child: Material(
                                color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: .6),
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => Navigator.pop(ctx, s.code),
                                  child: Center(
                                    child: Image.network(
                                      s.imageUrl,
                                      width: 32,
                                      height: 32,
                                      errorBuilder: (_, _, _) => Text(
                                        s.label,
                                        style: const TextStyle(fontSize: 12),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 选择一张图片并上传到论坛, 返回可插入正文的 `[attachimg]aid[/attachimg]`。
  /// 用户取消返回 null; 失败抛出可读异常。
  static Future<String> uploadImage(BuildContext context, int fid) async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
      type: FileType.image,
    );
    if (picked == null || picked.files.isEmpty) return ''; // 取消
    final file = picked.files.first;
    if (file.path == null || file.path!.isEmpty) {
      throw Exception('无法读取所选图片');
    }
    if (file.size > AttachmentUploadService.maxBytes) {
      throw Exception('图片不能超过 10 MB');
    }
    final uploaded = await AttachmentUploadService.instance.upload(fid: fid, file: file);
    return '[attachimg]${uploaded.aid}[/attachimg]';
  }

  /// 把 [text] 插入到 [controller] 的光标处, 忠实复刻论坛编辑器行为。
  static void insertAtCursor(TextEditingController controller, String text) {
    if (text.isEmpty) return;
    final value = controller.value;
    final s = value.selection;
    final start = s.isValid ? s.start.clamp(0, value.text.length).toInt() : value.text.length;
    final end = s.isValid ? s.end.clamp(0, value.text.length).toInt() : value.text.length;
    final newText = value.text.replaceRange(start, end, text);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: (start + text.length).clamp(0, newText.length).toInt()),
    );
  }
}