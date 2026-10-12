import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/config/app_backend.dart';
import 'package:wefilling/models/release_metadata.dart';
import 'package:wefilling/utils/profile_photo_policy.dart';

void main() {
  const legacy = BackendReleaseMetadata.legacyBucket;
  const kr = 'flutterproject3-af322-kr';

  tearDown(() => AppBackend.debugOverride(null));

  group('BackendReleaseMetadata', () {
    test('parses a valid backend block', () {
      final parsed = BackendReleaseMetadata.fromJson(<String, dynamic>{
        'functionsRegion': 'asia-northeast3',
        'uploadStorageBucket': kr,
        'legacyStorageBucket': legacy,
      });
      expect(parsed, isNotNull);
      expect(parsed!.functionsRegion, 'asia-northeast3');
      expect(parsed.uploadStorageBucket, kr);
      expect(parsed.knownBuckets, <String>{legacy, kr});
    });

    test('rejects malformed values instead of half-applying them', () {
      expect(
        BackendReleaseMetadata.fromJson(<String, dynamic>{
          'functionsRegion': 'Asia Northeast',
          'uploadStorageBucket': kr,
        }),
        isNull,
      );
      expect(
        BackendReleaseMetadata.fromJson(<String, dynamic>{
          'functionsRegion': 'us-central1',
          'uploadStorageBucket': 'gs://bad bucket',
        }),
        isNull,
      );
      expect(BackendReleaseMetadata.fromJson(null), isNull);
    });

    test('ReleaseMetadata decodes the backend block and tolerates its absence',
        () {
      final withBackend = ReleaseMetadata.decode('''
{"schemaVersion":1,"versionName":"1.3.24","buildNumber":94,
 "cacheSchemaVersion":1,"releaseChannel":"production","releaseId":"x",
 "firebaseProjectId":"flutterproject3-af322",
 "backend":{"functionsRegion":"asia-northeast3","uploadStorageBucket":"$kr"},
 "android":{},"ios":{},"migrations":{}}''');
      expect(withBackend.backend?.functionsRegion, 'asia-northeast3');
      expect(withBackend.backend?.legacyStorageBucket, legacy);

      final without = ReleaseMetadata.decode(
        '{"schemaVersion":1,"versionName":"1","buildNumber":1,'
        '"cacheSchemaVersion":1,"releaseChannel":"production","releaseId":"x",'
        '"firebaseProjectId":"p","android":{},"ios":{},"migrations":{}}',
      );
      expect(without.backend, isNull);
    });
  });

  group('AppBackend defaults', () {
    test('compile-time defaults match the shipped manifest shape', () {
      expect(AppBackend.defaults.isValid, isTrue);
      expect(AppBackend.defaults.legacyStorageBucket, legacy);
      // Without a loaded manifest the defaults are used.
      expect(AppBackend.config, same(AppBackend.defaults));
    });

    test('debugOverride wins over defaults', () {
      AppBackend.debugOverride(const BackendReleaseMetadata(
        functionsRegion: 'asia-northeast3',
        uploadStorageBucket: kr,
        legacyStorageBucket: legacy,
      ));
      expect(AppBackend.config.functionsRegion, 'asia-northeast3');
      expect(AppStorage.uploadBucketName, kr);
      expect(AppStorage.uploadsToLegacyBucket, isFalse);
    });
  });

  group('AppStorage bucket resolution', () {
    setUp(() {
      AppBackend.debugOverride(const BackendReleaseMetadata(
        functionsRegion: 'asia-northeast3',
        uploadStorageBucket: kr,
        legacyStorageBucket: legacy,
      ));
    });

    test('missing or empty bucket means legacy', () {
      expect(AppStorage.resolveBucketName(null), legacy);
      expect(AppStorage.resolveBucketName(''), legacy);
      expect(AppStorage.resolveBucketName('   '), legacy);
    });

    test('known buckets resolve, gs:// prefix and slashes are normalized', () {
      expect(AppStorage.resolveBucketName(kr), kr);
      expect(AppStorage.resolveBucketName('gs://$kr/'), kr);
      expect(AppStorage.resolveBucketName(legacy), legacy);
      expect(AppStorage.isKnownBucket('gs://$kr'), isTrue);
    });

    test('unknown buckets fall back to legacy', () {
      expect(AppStorage.resolveBucketName('evil-bucket'), legacy);
      expect(AppStorage.isKnownBucket('evil-bucket'), isFalse);
    });

    test('bucketFromUrl handles download, gs and XML URLs', () {
      expect(
        AppStorage.bucketFromUrl(
          'https://firebasestorage.googleapis.com/v0/b/$kr/o/'
          'snack_chat_images%2Fu%2Fr%2Fa.jpg?alt=media&token=t',
        ),
        kr,
      );
      expect(AppStorage.bucketFromUrl('gs://$legacy/profile_images/u/a.jpg'),
          legacy);
      expect(
        AppStorage.bucketFromUrl('https://storage.googleapis.com/$kr/a/b.jpg'),
        kr,
      );
      expect(AppStorage.bucketFromUrl('https://example.com/a.jpg'), isNull);
      expect(AppStorage.bucketFromUrl(''), isNull);
    });
  });

  group('ProfilePhotoPolicy with two buckets', () {
    setUp(() {
      AppBackend.debugOverride(const BackendReleaseMetadata(
        functionsRegion: 'asia-northeast3',
        uploadStorageBucket: kr,
        legacyStorageBucket: legacy,
      ));
    });

    test('accepts profile images from the legacy and the upload bucket', () {
      expect(
        ProfilePhotoPolicy.isAllowedProfilePhotoUrl(
          'https://firebasestorage.googleapis.com/v0/b/$legacy/o/'
          'profile_images%2Fuid%2Fa.jpg?alt=media&token=t',
        ),
        isTrue,
      );
      expect(
        ProfilePhotoPolicy.isAllowedProfilePhotoUrl(
          'https://firebasestorage.googleapis.com/v0/b/$kr/o/'
          'profile_images%2Fuid%2Fa.jpg?alt=media&token=t',
        ),
        isTrue,
      );
      expect(
        ProfilePhotoPolicy.isAllowedProfilePhotoUrl(
            'gs://$kr/profile_images/uid/a.jpg'),
        isTrue,
      );
    });

    test('still rejects foreign buckets, other folders and external hosts', () {
      expect(
        ProfilePhotoPolicy.isAllowedProfilePhotoUrl(
          'https://firebasestorage.googleapis.com/v0/b/other-bucket/o/'
          'profile_images%2Fuid%2Fa.jpg?alt=media',
        ),
        isFalse,
      );
      expect(
        ProfilePhotoPolicy.isAllowedProfilePhotoUrl(
          'https://firebasestorage.googleapis.com/v0/b/$kr/o/'
          'posts%2Fa.jpg?alt=media',
        ),
        isFalse,
      );
      expect(
        ProfilePhotoPolicy.isAllowedProfilePhotoUrl(
            'https://lh3.googleusercontent.com/a/photo.jpg'),
        isFalse,
      );
    });
  });
}
