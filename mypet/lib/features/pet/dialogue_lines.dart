import 'dart:math';

/// Preset dialogue pools. Add or edit lines here - no other file needs
/// changing. 统一猫娘语癖：全中文、句尾"喵"、不夹英文单词。
const Map<String, List<String>> linePools = {
  'idle': [
    '今天也要加油喵！',
    '车站的风好舒服呀~',
    '今天想吃什么好吃的喵？',
    '主人在忙什么呢？要记得休息喵',
    '嘿嘿，你也在偷懒喵？',
    '花开了，春天来了喵',
  ],
  'head': [
    '别戳了，好痒喵~',
    '摸摸头可以，但要轻一点喵',
    '唔...耳朵要被揉乱了喵！',
    '再摸一会儿...就一会儿喵',
  ],
  'body': [
    '抱...抱不动喵！',
    '痒痒痒！别挠了喵！',
    '裙子会被弄皱的喵！',
  ],
  'tail': [
    '尾巴...不许拽喵！',
    '喵！尾巴很敏感的喵！',
    '摇尾巴是因为开心喵',
  ],
  'sleep': [
    '困了喵...Zzz...',
    '好困...陪我睡一会儿喵...',
    '呼呼...梦里也在吃小鱼干喵...',
  ],
};

/// 设置面板里的编辑顺序与显示名。
const List<String> dialogueKeys = ['idle', 'head', 'body', 'tail', 'sleep'];

const Map<String, String> dialogueLabels = {
  'idle': '闲置随机搭话',
  'head': '点击头部',
  'body': '点击身体',
  'tail': '点击尾巴',
  'sleep': '打瞌睡',
};

List<String> defaultLines(String key) => linePools[key] ?? const <String>[];

/// 取一条台词。[overrides] 是用户在设置面板里写的自定义台词
/// （每行一条）：该键存在且非空时优先，否则回退内置默认。
String pickLine(String key, [Random? rng, Map<String, List<String>>? overrides]) {
  final r = rng ?? Random();
  final custom = overrides?[key];
  final builtin = linePools[key];
  final List<String> pool;
  if (custom != null && custom.isNotEmpty) {
    pool = custom;
  } else if (builtin != null && builtin.isNotEmpty) {
    pool = builtin;
  } else {
    pool = linePools['idle']!;
  }
  return pool[r.nextInt(pool.length)];
}
