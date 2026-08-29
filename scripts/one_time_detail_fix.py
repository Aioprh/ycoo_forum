from pathlib import Path
import re

api = Path('lib/services/api_service.dart')
s = api.read_text()
new_collect = '''  static List<String> _collectPosts(dom.Document doc) {
    final out = <String>[];
    final containers = doc.querySelectorAll(
      '.comiis_postli, #postlist .plhin, #postlist .plc, #postlist > div[id^="post_"]',
    );

    String? extract(dom.Element post) {
      final selectors = <String>[
        '[id^="postmessage_"]',
        '.t_f',
        '.pcb',
        '.comiis_postcontent',
        '.comiis_message',
        '.message',
        '.postmessage',
      ];
      for (final selector in selectors) {
        final node = post.querySelector(selector);
        if (node == null) continue;
        final html = node.innerHtml.trim();
        final text = _normSpace(node.text);
        if (html.isEmpty) continue;
        if (text.contains('本主题需向作者支付') ||
            (text.contains('购买主题') && text.contains('星币'))) continue;
        return html;
      }
      return null;
    }

    for (final post in containers) {
      final html = extract(post);
      if (html == null) continue;
      final author = _normSpace(post.querySelector('.top_user, .authi .xw1, .authi a')?.text ?? '');
      final level = _normSpace(post.querySelector('.top_lev, .p_pop')?.text ?? '');
      final floor = _normSpace(post.querySelector('.f_d.y, .pi .authi em, .pls .authi em')?.text ?? '')
          .replaceAll(RegExp(r'[^0-9A-Za-z一二三四五六七八九十楼主]'), '');
      final time = _normSpace(post.querySelector('.kmtime, .comiis_tm, .authi em')?.text ?? '');
      final displayFloor = floor.isEmpty ? (out.isEmpty ? '楼主' : '${out.length + 1}楼') : floor;
      out.add(
        '<div class="post-card"><div class="post-hd"><span class="p-floor">$displayFloor</span>'
        '${author.isEmpty ? '' : '<b class="p-author">$author</b>'}'
        '${level.isEmpty ? '' : '<span class="p-level">$level</span>'}</div>'
        '${time.isEmpty ? '' : '<div class="p-time">$time</div>'}'
        '<div class="p-body">${_cleanPostHtml(html)}</div></div>',
      );
    }

    if (out.isEmpty) {
      for (final node in doc.querySelectorAll('[id^="postmessage_"], .t_f, .pcb')) {
        final html = node.innerHtml.trim();
        final text = _normSpace(node.text);
        if (html.isEmpty || text.contains('本主题需向作者支付') ||
            (text.contains('购买主题') && text.contains('星币'))) continue;
        out.add('<div class="post-card"><div class="p-body">${_cleanPostHtml(html)}</div></div>');
      }
    }
    return out;
  }
'''
s, n = re.subn(r'  static List<String> _collectPosts\(dom\.Document doc\) \{.*?\n  static String _cleanPostHtml', new_collect + '\n  static String _cleanPostHtml', s, count=1, flags=re.S)
if n != 1:
    raise SystemExit('api_service: _collectPosts not found')
api.write_text(s)

page = Path('lib/pages/detail_page.dart')
s = page.read_text()
old = '''  Future<void> _fetch() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final d = await ApiService.instance.fetchThreadDetail(widget.tid);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _likeCount = d.likeCount;
        _liked = d.likedByMe;
        _bodyHeight = 0;
      });
      _bodyController = d.bodyHtml.trim().isEmpty ? null : _web(d.bodyHtml);
      if (_loggedIn) await _loadInteractionState();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
'''
new = '''  Future<void> _fetch() async {
    final hadDetail = _detail != null;
    if (mounted) {
      setState(() {
        _loading = !hadDetail;
        _error = null;
      });
    }
    try {
      final d = await ApiService.instance.fetchThreadDetail(widget.tid);
      if (!mounted) return;
      final oldBody = _detail?.bodyHtml.trim() ?? '';
      final newBody = d.bodyHtml.trim();
      final bodyChanged = oldBody != newBody;
      setState(() {
        _detail = d;
        _likeCount = d.likeCount;
        _liked = d.likedByMe;
        if (newBody.isEmpty) {
          _bodyController = null;
          _bodyHeight = 0;
        } else if (bodyChanged || _bodyController == null) {
          _bodyHeight = 0;
        }
      });
      if (newBody.isNotEmpty && (bodyChanged || _bodyController == null)) {
        _bodyController = _web(newBody);
      }
      if (_loggedIn) await _loadInteractionState();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
'''
if old not in s:
    raise SystemExit('detail_page: _fetch not found')
s = s.replace(old, new, 1)
old_js = """              final raw = await controller.runJavaScriptReturningResult(
                'Math.max(document.body.scrollHeight,document.documentElement.scrollHeight)',
              );"""
new_js = """              final raw = await controller.runJavaScriptReturningResult(
                '''(function(){
                  document.querySelectorAll('[style]').forEach(function(e){
                    var st=(e.getAttribute('style')||'').replace(/\\s/g,'').toLowerCase();
                    if(st.indexOf('100vh')>=0 || st.indexOf('min-height:')>=0 || st.indexOf('height:100%')>=0) e.style.minHeight='0';
                  });
                  return Math.max(document.body.scrollHeight,document.documentElement.scrollHeight);
                })()''',
              );"""
if old_js not in s:
    raise SystemExit('detail_page: height script not found')
s = s.replace(old_js, new_js, 1)
page.write_text(s)
