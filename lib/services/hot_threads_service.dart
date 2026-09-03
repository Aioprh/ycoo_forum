import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import '../models/thread_item.dart';
import 'auth_service.dart';
import 'net_client.dart';
import 'site_config.dart';
class HotThreadsService {
  HotThreadsService._();
  static final instance = HotThreadsService._();
  static String get _base => SiteConfig.base;
  static final _canonical = '${SiteConfig.base}forum.php?mod=guide&view=hot&index=1';
  Future<List<ThreadItem>> fetch() async { return const <ThreadItem>[]; }
}
