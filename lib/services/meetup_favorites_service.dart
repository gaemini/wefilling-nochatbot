import 'package:shared_preferences/shared_preferences.dart';
import '../models/meetup_favorite_template.dart';

class MeetupFavoritesService {
  static const String _storageKey = 'meetup_favorite_templates_v1';

  Future<List<MeetupFavoriteTemplate>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return [];

    final list = MeetupFavoriteTemplate.listFromEncoded(raw);
    // 최신순 정렬
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<void> saveAll(List<MeetupFavoriteTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = MeetupFavoriteTemplate.listToEncoded(templates);
    await prefs.setString(_storageKey, encoded);
  }

  Future<List<MeetupFavoriteTemplate>> upsert(MeetupFavoriteTemplate template) async {
    final list = await load();
    final idx = list.indexWhere((t) => t.id == template.id);
    final updated = template.copyWith(updatedAt: DateTime.now());
    if (idx >= 0) {
      list[idx] = updated;
    } else {
      list.insert(0, updated);
    }
    await saveAll(list);
    return list;
  }

  Future<List<MeetupFavoriteTemplate>> deleteById(String id) async {
    final list = await load();
    list.removeWhere((t) => t.id == id);
    await saveAll(list);
    return list;
  }
}

