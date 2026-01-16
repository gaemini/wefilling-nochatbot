import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko')
  ];

  /// No description provided for @login.
  ///
  /// In ko, this message translates to:
  /// **'로그인'**
  String get login;

  /// No description provided for @signUp.
  ///
  /// In ko, this message translates to:
  /// **'회원가입'**
  String get signUp;

  /// No description provided for @logout.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃'**
  String get logout;

  /// No description provided for @logoutConfirm.
  ///
  /// In ko, this message translates to:
  /// **'정말 로그아웃하시겠습니까?'**
  String get logoutConfirm;

  /// No description provided for @logoutSuccess.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃되었습니다'**
  String get logoutSuccess;

  /// No description provided for @logoutError.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃 중 오류가 발생했습니다.\n다시 시도해주세요.'**
  String get logoutError;

  /// No description provided for @offlineLogout.
  ///
  /// In ko, this message translates to:
  /// **'오프라인 상태에서 로그아웃되었습니다'**
  String get offlineLogout;

  /// No description provided for @loggingOut.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃 중...'**
  String get loggingOut;

  /// No description provided for @email.
  ///
  /// In ko, this message translates to:
  /// **'이메일'**
  String get email;

  /// No description provided for @password.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 확인'**
  String get confirmPassword;

  /// No description provided for @forgotPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 잊으셨나요?'**
  String get forgotPassword;

  /// No description provided for @resetPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 재설정'**
  String get resetPassword;

  /// No description provided for @sendResetEmail.
  ///
  /// In ko, this message translates to:
  /// **'재설정 이메일 보내기'**
  String get sendResetEmail;

  /// No description provided for @loginFailed.
  ///
  /// In ko, this message translates to:
  /// **'로그인에 실패했습니다. 이메일과 비밀번호를 확인해주세요.'**
  String get loginFailed;

  /// No description provided for @loginError.
  ///
  /// In ko, this message translates to:
  /// **'로그인 중 오류가 발생했습니다'**
  String get loginError;

  /// No description provided for @loginRequired.
  ///
  /// In ko, this message translates to:
  /// **'로그인이 필요합니다'**
  String get loginRequired;

  /// No description provided for @emailSent.
  ///
  /// In ko, this message translates to:
  /// **'이메일을 보냈습니다. 메일함을 확인해주세요.'**
  String get emailSent;

  /// No description provided for @verificationEmailSent.
  ///
  /// In ko, this message translates to:
  /// **'인증 이메일을 보냈습니다. 메일함을 확인해주세요.'**
  String get verificationEmailSent;

  /// No description provided for @resetEmailSent.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 재설정 이메일을 보냈습니다.'**
  String get resetEmailSent;

  /// No description provided for @sendResetEmailConfirm.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 재설정 이메일을 보내시겠습니까?'**
  String get sendResetEmailConfirm;

  /// No description provided for @board.
  ///
  /// In ko, this message translates to:
  /// **'게시글'**
  String get board;

  /// No description provided for @meetup.
  ///
  /// In ko, this message translates to:
  /// **'모임'**
  String get meetup;

  /// No description provided for @myPage.
  ///
  /// In ko, this message translates to:
  /// **'내 정보'**
  String get myPage;

  /// No description provided for @home.
  ///
  /// In ko, this message translates to:
  /// **'홈'**
  String get home;

  /// No description provided for @friends.
  ///
  /// In ko, this message translates to:
  /// **'친구'**
  String get friends;

  /// No description provided for @notifications.
  ///
  /// In ko, this message translates to:
  /// **'알림'**
  String get notifications;

  /// No description provided for @settings.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get settings;

  /// No description provided for @accountSettings.
  ///
  /// In ko, this message translates to:
  /// **'계정 설정'**
  String get accountSettings;

  /// No description provided for @language.
  ///
  /// In ko, this message translates to:
  /// **'언어'**
  String get language;

  /// No description provided for @languageSettings.
  ///
  /// In ko, this message translates to:
  /// **'언어 설정'**
  String get languageSettings;

  /// No description provided for @selectLanguage.
  ///
  /// In ko, this message translates to:
  /// **'언어 선택'**
  String get selectLanguage;

  /// No description provided for @notificationSettings.
  ///
  /// In ko, this message translates to:
  /// **'알림 설정'**
  String get notificationSettings;

  /// No description provided for @privacyPolicy.
  ///
  /// In ko, this message translates to:
  /// **'개인정보 처리방침'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In ko, this message translates to:
  /// **'서비스 이용약관'**
  String get termsOfService;

  /// No description provided for @deleteAccount.
  ///
  /// In ko, this message translates to:
  /// **'계정 삭제'**
  String get deleteAccount;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In ko, this message translates to:
  /// **'정말로 탈퇴하시겠습니까? 모든 데이터가 삭제됩니다.'**
  String get deleteAccountConfirm;

  /// No description provided for @deleteAccountCompleted.
  ///
  /// In ko, this message translates to:
  /// **'회원 탈퇴가 완료되었습니다'**
  String get deleteAccountCompleted;

  /// No description provided for @userNotFound.
  ///
  /// In ko, this message translates to:
  /// **'로그인된 사용자를 찾을 수 없습니다'**
  String get userNotFound;

  /// No description provided for @confirm.
  ///
  /// In ko, this message translates to:
  /// **'확인'**
  String get confirm;

  /// No description provided for @cancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In ko, this message translates to:
  /// **'수정'**
  String get edit;

  /// No description provided for @create.
  ///
  /// In ko, this message translates to:
  /// **'만들기'**
  String get create;

  /// No description provided for @createAction.
  ///
  /// In ko, this message translates to:
  /// **'생성'**
  String get createAction;

  /// No description provided for @search.
  ///
  /// In ko, this message translates to:
  /// **'검색'**
  String get search;

  /// No description provided for @searchMeetups.
  ///
  /// In ko, this message translates to:
  /// **'모임 검색'**
  String get searchMeetups;

  /// No description provided for @searching.
  ///
  /// In ko, this message translates to:
  /// **'검색하기'**
  String get searching;

  /// No description provided for @searchByName.
  ///
  /// In ko, this message translates to:
  /// **'친구 이름으로 검색'**
  String get searchByName;

  /// No description provided for @loading.
  ///
  /// In ko, this message translates to:
  /// **'로딩 중...'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In ko, this message translates to:
  /// **'오류가 발생했습니다'**
  String get error;

  /// No description provided for @success.
  ///
  /// In ko, this message translates to:
  /// **'성공'**
  String get success;

  /// No description provided for @warning.
  ///
  /// In ko, this message translates to:
  /// **'경고'**
  String get warning;

  /// No description provided for @info.
  ///
  /// In ko, this message translates to:
  /// **'정보'**
  String get info;

  /// No description provided for @yes.
  ///
  /// In ko, this message translates to:
  /// **'예'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In ko, this message translates to:
  /// **'아니오'**
  String get no;

  /// No description provided for @ok.
  ///
  /// In ko, this message translates to:
  /// **'확인'**
  String get ok;

  /// No description provided for @done.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get done;

  /// No description provided for @registration.
  ///
  /// In ko, this message translates to:
  /// **'등록'**
  String get registration;

  /// No description provided for @back.
  ///
  /// In ko, this message translates to:
  /// **'이전'**
  String get back;

  /// No description provided for @next.
  ///
  /// In ko, this message translates to:
  /// **'다음'**
  String get next;

  /// No description provided for @submit.
  ///
  /// In ko, this message translates to:
  /// **'제출'**
  String get submit;

  /// No description provided for @retry.
  ///
  /// In ko, this message translates to:
  /// **'재시도'**
  String get retry;

  /// No description provided for @retryAction.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get retryAction;

  /// No description provided for @close.
  ///
  /// In ko, this message translates to:
  /// **'닫기'**
  String get close;

  /// No description provided for @later.
  ///
  /// In ko, this message translates to:
  /// **'나중에'**
  String get later;

  /// No description provided for @all.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get all;

  /// No description provided for @allMeetups.
  ///
  /// In ko, this message translates to:
  /// **'모든 모임'**
  String get allMeetups;

  /// No description provided for @author.
  ///
  /// In ko, this message translates to:
  /// **'글쓴이'**
  String get author;

  /// No description provided for @post.
  ///
  /// In ko, this message translates to:
  /// **'게시글'**
  String get post;

  /// No description provided for @posts.
  ///
  /// In ko, this message translates to:
  /// **'게시글'**
  String get posts;

  /// No description provided for @createPost.
  ///
  /// In ko, this message translates to:
  /// **'게시글 작성'**
  String get createPost;

  /// No description provided for @newPost.
  ///
  /// In ko, this message translates to:
  /// **'새 게시글 작성'**
  String get newPost;

  /// No description provided for @newPostCreation.
  ///
  /// In ko, this message translates to:
  /// **'새 게시글 작성'**
  String get newPostCreation;

  /// No description provided for @editPost.
  ///
  /// In ko, this message translates to:
  /// **'게시글 수정'**
  String get editPost;

  /// No description provided for @deletePost.
  ///
  /// In ko, this message translates to:
  /// **'게시글 삭제'**
  String get deletePost;

  /// No description provided for @postDetail.
  ///
  /// In ko, this message translates to:
  /// **'게시글 상세'**
  String get postDetail;

  /// No description provided for @writePost.
  ///
  /// In ko, this message translates to:
  /// **'글 작성하기'**
  String get writePost;

  /// No description provided for @postCreated.
  ///
  /// In ko, this message translates to:
  /// **'게시글이 등록되었습니다.'**
  String get postCreated;

  /// No description provided for @postCreateFailed.
  ///
  /// In ko, this message translates to:
  /// **'게시글 등록에 실패했습니다. 다시 시도해주세요.'**
  String get postCreateFailed;

  /// No description provided for @postDeleted.
  ///
  /// In ko, this message translates to:
  /// **'게시글이 삭제되었습니다.'**
  String get postDeleted;

  /// No description provided for @postDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'게시글 삭제에 실패했습니다.'**
  String get postDeleteFailed;

  /// No description provided for @title.
  ///
  /// In ko, this message translates to:
  /// **'제목'**
  String get title;

  /// No description provided for @enterTitle.
  ///
  /// In ko, this message translates to:
  /// **'제목을 입력하세요'**
  String get enterTitle;

  /// No description provided for @content.
  ///
  /// In ko, this message translates to:
  /// **'내용'**
  String get content;

  /// No description provided for @enterContent.
  ///
  /// In ko, this message translates to:
  /// **'내용을 입력하세요'**
  String get enterContent;

  /// No description provided for @image.
  ///
  /// In ko, this message translates to:
  /// **'이미지'**
  String get image;

  /// No description provided for @images.
  ///
  /// In ko, this message translates to:
  /// **'이미지'**
  String get images;

  /// No description provided for @selectImage.
  ///
  /// In ko, this message translates to:
  /// **'이미지 선택'**
  String get selectImage;

  /// No description provided for @imageAttachment.
  ///
  /// In ko, this message translates to:
  /// **'이미지 첨부'**
  String get imageAttachment;

  /// No description provided for @imageSelected.
  ///
  /// In ko, this message translates to:
  /// **'이미지가 선택되었습니다'**
  String get imageSelected;

  /// No description provided for @imageSelectError.
  ///
  /// In ko, this message translates to:
  /// **'이미지 선택 중 오류가 발생했습니다.'**
  String get imageSelectError;

  /// No description provided for @imageUploading.
  ///
  /// In ko, this message translates to:
  /// **'이미지를 업로드 중입니다. 잠시만 기다려주세요...'**
  String get imageUploading;

  /// No description provided for @selectFromGallery.
  ///
  /// In ko, this message translates to:
  /// **'갤러리에서 선택'**
  String get selectFromGallery;

  /// No description provided for @takePhoto.
  ///
  /// In ko, this message translates to:
  /// **'사진 촬영'**
  String get takePhoto;

  /// No description provided for @photoError.
  ///
  /// In ko, this message translates to:
  /// **'사진 촬영 중 오류가 발생했습니다.'**
  String get photoError;

  /// No description provided for @useDefaultImage.
  ///
  /// In ko, this message translates to:
  /// **'기본 이미지 사용'**
  String get useDefaultImage;

  /// No description provided for @imageDisplayIssue.
  ///
  /// In ko, this message translates to:
  /// **'이미지 표시 문제 감지'**
  String get imageDisplayIssue;

  /// No description provided for @troubleshoot.
  ///
  /// In ko, this message translates to:
  /// **'문제 해결하기'**
  String get troubleshoot;

  /// No description provided for @noPostsYet.
  ///
  /// In ko, this message translates to:
  /// **'등록된 게시글이 없습니다'**
  String get noPostsYet;

  /// No description provided for @like.
  ///
  /// In ko, this message translates to:
  /// **'좋아요'**
  String get like;

  /// No description provided for @comment.
  ///
  /// In ko, this message translates to:
  /// **'댓글'**
  String get comment;

  /// No description provided for @comments.
  ///
  /// In ko, this message translates to:
  /// **'Comments'**
  String get comments;

  /// No description provided for @writeComment.
  ///
  /// In ko, this message translates to:
  /// **'댓글을 입력하세요...'**
  String get writeComment;

  /// No description provided for @commentCreated.
  ///
  /// In ko, this message translates to:
  /// **'댓글이 등록되었습니다.'**
  String get commentCreated;

  /// No description provided for @commentCreateFailed.
  ///
  /// In ko, this message translates to:
  /// **'댓글 등록에 실패했습니다.'**
  String get commentCreateFailed;

  /// No description provided for @commentDeleted.
  ///
  /// In ko, this message translates to:
  /// **'댓글이 삭제되었습니다.'**
  String get commentDeleted;

  /// No description provided for @commentDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'댓글 삭제에 실패했습니다.'**
  String get commentDeleteFailed;

  /// No description provided for @share.
  ///
  /// In ko, this message translates to:
  /// **'공유'**
  String get share;

  /// No description provided for @report.
  ///
  /// In ko, this message translates to:
  /// **'신고'**
  String get report;

  /// No description provided for @reportSubmitted.
  ///
  /// In ko, this message translates to:
  /// **'신고가 접수되었습니다'**
  String get reportSubmitted;

  /// No description provided for @reportAction.
  ///
  /// In ko, this message translates to:
  /// **'신고하기'**
  String get reportAction;

  /// No description provided for @blockUser.
  ///
  /// In ko, this message translates to:
  /// **'사용자 차단'**
  String get blockUser;

  /// No description provided for @userBlocked.
  ///
  /// In ko, this message translates to:
  /// **'사용자를 차단했습니다'**
  String get userBlocked;

  /// No description provided for @visibilityScope.
  ///
  /// In ko, this message translates to:
  /// **'공개 범위'**
  String get visibilityScope;

  /// No description provided for @publicPost.
  ///
  /// In ko, this message translates to:
  /// **'전체 공개'**
  String get publicPost;

  /// No description provided for @categorySpecific.
  ///
  /// In ko, this message translates to:
  /// **'카테고리별'**
  String get categorySpecific;

  /// No description provided for @authorAndCommenterInfo.
  ///
  /// In ko, this message translates to:
  /// **'작성자와 댓 작성자의 설명이 표시됩니다'**
  String get authorAndCommenterInfo;

  /// No description provided for @postAnonymously.
  ///
  /// In ko, this message translates to:
  /// **'익명으로 게시'**
  String get postAnonymously;

  /// No description provided for @anonymous.
  ///
  /// In ko, this message translates to:
  /// **'익명'**
  String get anonymous;

  /// No description provided for @private.
  ///
  /// In ko, this message translates to:
  /// **'비공개'**
  String get private;

  /// No description provided for @idWillBeShown.
  ///
  /// In ko, this message translates to:
  /// **'아이디가 공개됩니다'**
  String get idWillBeShown;

  /// No description provided for @createMeetup.
  ///
  /// In ko, this message translates to:
  /// **'모임 만들기'**
  String get createMeetup;

  /// No description provided for @createNewMeetup.
  ///
  /// In ko, this message translates to:
  /// **'새로운 모임 생성'**
  String get createNewMeetup;

  /// No description provided for @createFirstMeetup.
  ///
  /// In ko, this message translates to:
  /// **'첫 모임 만들기'**
  String get createFirstMeetup;

  /// No description provided for @editMeetup.
  ///
  /// In ko, this message translates to:
  /// **'모임 수정'**
  String get editMeetup;

  /// No description provided for @deleteMeetup.
  ///
  /// In ko, this message translates to:
  /// **'모임 삭제'**
  String get deleteMeetup;

  /// No description provided for @cancelMeetup.
  ///
  /// In ko, this message translates to:
  /// **'모임 취소'**
  String get cancelMeetup;

  /// No description provided for @cancelMeetupConfirm.
  ///
  /// In ko, this message translates to:
  /// **'모임 취소 확인'**
  String get cancelMeetupConfirm;

  /// No description provided for @meetupDetail.
  ///
  /// In ko, this message translates to:
  /// **'모임 상세'**
  String get meetupDetail;

  /// No description provided for @joinMeetup.
  ///
  /// In ko, this message translates to:
  /// **'참여하기'**
  String get joinMeetup;

  /// No description provided for @join.
  ///
  /// In ko, this message translates to:
  /// **'참여'**
  String get join;

  /// No description provided for @participating.
  ///
  /// In ko, this message translates to:
  /// **'참여중'**
  String get participating;

  /// No description provided for @leaveMeetup.
  ///
  /// In ko, this message translates to:
  /// **'나가기'**
  String get leaveMeetup;

  /// No description provided for @meetupTitle.
  ///
  /// In ko, this message translates to:
  /// **'모임 제목'**
  String get meetupTitle;

  /// No description provided for @enterMeetupTitle.
  ///
  /// In ko, this message translates to:
  /// **'모임 제목을 입력하세요'**
  String get enterMeetupTitle;

  /// No description provided for @meetupDescription.
  ///
  /// In ko, this message translates to:
  /// **'모임 설명'**
  String get meetupDescription;

  /// No description provided for @enterMeetupDescription.
  ///
  /// In ko, this message translates to:
  /// **'모임에 대한 설명을 입력해주세요'**
  String get enterMeetupDescription;

  /// No description provided for @meetupInfo.
  ///
  /// In ko, this message translates to:
  /// **'모임 정보'**
  String get meetupInfo;

  /// No description provided for @meetupCreated.
  ///
  /// In ko, this message translates to:
  /// **'모임이 생성되었습니다!'**
  String get meetupCreated;

  /// No description provided for @meetupUpdated.
  ///
  /// In ko, this message translates to:
  /// **'모임 정보가 업데이트되었습니다.'**
  String get meetupUpdated;

  /// No description provided for @meetupUpdateSuccess.
  ///
  /// In ko, this message translates to:
  /// **'모임이 성공적으로 수정되었습니다.'**
  String get meetupUpdateSuccess;

  /// No description provided for @meetupCancelled.
  ///
  /// In ko, this message translates to:
  /// **'모임이 취소되었습니다'**
  String get meetupCancelled;

  /// No description provided for @meetupCancelSuccess.
  ///
  /// In ko, this message translates to:
  /// **'모임이 성공적으로 취소되었습니다.'**
  String get meetupCancelSuccess;

  /// No description provided for @meetupCancelFailed.
  ///
  /// In ko, this message translates to:
  /// **'모임 취소에 실패했습니다. 다시 시도해주세요.'**
  String get meetupCancelFailed;

  /// No description provided for @location.
  ///
  /// In ko, this message translates to:
  /// **'장소'**
  String get location;

  /// No description provided for @date.
  ///
  /// In ko, this message translates to:
  /// **'날짜'**
  String get date;

  /// No description provided for @dateSelection.
  ///
  /// In ko, this message translates to:
  /// **'날짜 선택'**
  String get dateSelection;

  /// No description provided for @time.
  ///
  /// In ko, this message translates to:
  /// **'시간'**
  String get time;

  /// No description provided for @maxParticipants.
  ///
  /// In ko, this message translates to:
  /// **'최대 인원'**
  String get maxParticipants;

  /// No description provided for @currentParticipants.
  ///
  /// In ko, this message translates to:
  /// **'현재 인원'**
  String get currentParticipants;

  /// No description provided for @participants.
  ///
  /// In ko, this message translates to:
  /// **'참여자'**
  String get participants;

  /// No description provided for @host.
  ///
  /// In ko, this message translates to:
  /// **'주최자'**
  String get host;

  /// No description provided for @category.
  ///
  /// In ko, this message translates to:
  /// **'카테고리'**
  String get category;

  /// No description provided for @categories.
  ///
  /// In ko, this message translates to:
  /// **'카테고리'**
  String get categories;

  /// No description provided for @study.
  ///
  /// In ko, this message translates to:
  /// **'스터디'**
  String get study;

  /// No description provided for @meal.
  ///
  /// In ko, this message translates to:
  /// **'식사'**
  String get meal;

  /// No description provided for @hobby.
  ///
  /// In ko, this message translates to:
  /// **'카페'**
  String get hobby;

  /// No description provided for @culture.
  ///
  /// In ko, this message translates to:
  /// **'문화'**
  String get culture;

  /// No description provided for @noMeetupsYet.
  ///
  /// In ko, this message translates to:
  /// **'등록된 모임이 없습니다'**
  String get noMeetupsYet;

  /// No description provided for @meetupJoined.
  ///
  /// In ko, this message translates to:
  /// **'모임에 참여 신청이 완료되었습니다!'**
  String get meetupJoined;

  /// No description provided for @meetupFull.
  ///
  /// In ko, this message translates to:
  /// **'모임이 가득 찼습니다'**
  String get meetupFull;

  /// No description provided for @meetupClosed.
  ///
  /// In ko, this message translates to:
  /// **'종료된 모임입니다'**
  String get meetupClosed;

  /// No description provided for @hostedMeetups.
  ///
  /// In ko, this message translates to:
  /// **'주최한 모임'**
  String get hostedMeetups;

  /// No description provided for @joinedMeetups.
  ///
  /// In ko, this message translates to:
  /// **'참여한 모임'**
  String get joinedMeetups;

  /// No description provided for @writtenPosts.
  ///
  /// In ko, this message translates to:
  /// **'작성한 글'**
  String get writtenPosts;

  /// No description provided for @profile.
  ///
  /// In ko, this message translates to:
  /// **'프로필'**
  String get profile;

  /// No description provided for @editProfile.
  ///
  /// In ko, this message translates to:
  /// **'프로필 수정'**
  String get editProfile;

  /// No description provided for @profileEdit.
  ///
  /// In ko, this message translates to:
  /// **'프로필 편집'**
  String get profileEdit;

  /// No description provided for @nickname.
  ///
  /// In ko, this message translates to:
  /// **'닉네임'**
  String get nickname;

  /// No description provided for @bio.
  ///
  /// In ko, this message translates to:
  /// **'소개'**
  String get bio;

  /// No description provided for @profileImage.
  ///
  /// In ko, this message translates to:
  /// **'프로필 이미지'**
  String get profileImage;

  /// No description provided for @myPosts.
  ///
  /// In ko, this message translates to:
  /// **'내 게시글'**
  String get myPosts;

  /// No description provided for @myMeetups.
  ///
  /// In ko, this message translates to:
  /// **'내 모임'**
  String get myMeetups;

  /// No description provided for @myComments.
  ///
  /// In ko, this message translates to:
  /// **'내 댓글'**
  String get myComments;

  /// No description provided for @review.
  ///
  /// In ko, this message translates to:
  /// **'후기'**
  String get review;

  /// No description provided for @reviews.
  ///
  /// In ko, this message translates to:
  /// **'후기'**
  String get reviews;

  /// No description provided for @checkReview.
  ///
  /// In ko, this message translates to:
  /// **'후기 확인'**
  String get checkReview;

  /// No description provided for @saved.
  ///
  /// In ko, this message translates to:
  /// **'저장된'**
  String get saved;

  /// No description provided for @yourStoryMatters.
  ///
  /// In ko, this message translates to:
  /// **'카테고리를 사용해서'**
  String get yourStoryMatters;

  /// No description provided for @shareYourMoments.
  ///
  /// In ko, this message translates to:
  /// **'부담 없이, 감성 없이\n있는 그대로 공유해보세요.'**
  String get shareYourMoments;

  /// No description provided for @writeStory.
  ///
  /// In ko, this message translates to:
  /// **'이야기 남기기'**
  String get writeStory;

  /// No description provided for @wefillingMeaning.
  ///
  /// In ko, this message translates to:
  /// **'Wefilling의 뜻을 아시나요?'**
  String get wefillingMeaning;

  /// No description provided for @wefillingExplanation.
  ///
  /// In ko, this message translates to:
  /// **'\"We\"와 \"filling\"의 합성어로,\n사람과 사람 사이의 공간을 채운다는 뜻입니다.'**
  String get wefillingExplanation;

  /// No description provided for @friendRequest.
  ///
  /// In ko, this message translates to:
  /// **'친구 요청'**
  String get friendRequest;

  /// No description provided for @friendRequests.
  ///
  /// In ko, this message translates to:
  /// **'친구 요청'**
  String get friendRequests;

  /// No description provided for @friendsList.
  ///
  /// In ko, this message translates to:
  /// **'친구'**
  String get friendsList;

  /// No description provided for @acceptFriend.
  ///
  /// In ko, this message translates to:
  /// **'수락'**
  String get acceptFriend;

  /// No description provided for @accept.
  ///
  /// In ko, this message translates to:
  /// **'수락'**
  String get accept;

  /// No description provided for @rejectFriend.
  ///
  /// In ko, this message translates to:
  /// **'거절'**
  String get rejectFriend;

  /// No description provided for @reject.
  ///
  /// In ko, this message translates to:
  /// **'거절'**
  String get reject;

  /// No description provided for @approved.
  ///
  /// In ko, this message translates to:
  /// **'승인됨'**
  String get approved;

  /// No description provided for @rejected.
  ///
  /// In ko, this message translates to:
  /// **'거절됨'**
  String get rejected;

  /// No description provided for @pending.
  ///
  /// In ko, this message translates to:
  /// **'대기중'**
  String get pending;

  /// No description provided for @inProgress.
  ///
  /// In ko, this message translates to:
  /// **'진행중'**
  String get inProgress;

  /// No description provided for @expired.
  ///
  /// In ko, this message translates to:
  /// **'만료된 요청'**
  String get expired;

  /// No description provided for @addFriend.
  ///
  /// In ko, this message translates to:
  /// **'친구 추가'**
  String get addFriend;

  /// No description provided for @removeFriend.
  ///
  /// In ko, this message translates to:
  /// **'친구 삭제'**
  String get removeFriend;

  /// No description provided for @friendList.
  ///
  /// In ko, this message translates to:
  /// **'친구 목록'**
  String get friendList;

  /// No description provided for @block.
  ///
  /// In ko, this message translates to:
  /// **'차단'**
  String get block;

  /// No description provided for @unblock.
  ///
  /// In ko, this message translates to:
  /// **'차단 해제'**
  String get unblock;

  /// No description provided for @blockedUsers.
  ///
  /// In ko, this message translates to:
  /// **'차단한 사용자'**
  String get blockedUsers;

  /// No description provided for @requests.
  ///
  /// In ko, this message translates to:
  /// **'요청'**
  String get requests;

  /// No description provided for @myFriendsOnly.
  ///
  /// In ko, this message translates to:
  /// **'내 친구들만 볼 수 있습니다'**
  String get myFriendsOnly;

  /// No description provided for @everyoneCanSee.
  ///
  /// In ko, this message translates to:
  /// **'모든 사용자가 볼 수 있습니다'**
  String get everyoneCanSee;

  /// No description provided for @selectedGroupOnly.
  ///
  /// In ko, this message translates to:
  /// **'선택한 그룹의 친구들만 이 모임을 볼 수 있습니다'**
  String get selectedGroupOnly;

  /// No description provided for @selectedFriendGroupOnly.
  ///
  /// In ko, this message translates to:
  /// **'선택한 친구 그룹만'**
  String get selectedFriendGroupOnly;

  /// No description provided for @noGroup.
  ///
  /// In ko, this message translates to:
  /// **'그룹 없음'**
  String get noGroup;

  /// No description provided for @groupSettings.
  ///
  /// In ko, this message translates to:
  /// **'카테고리 설정'**
  String get groupSettings;

  /// No description provided for @selectCategoriesToShare.
  ///
  /// In ko, this message translates to:
  /// **'공개할 카테고리 선택'**
  String get selectCategoriesToShare;

  /// No description provided for @friendCategories.
  ///
  /// In ko, this message translates to:
  /// **'친구 카테고리'**
  String get friendCategories;

  /// No description provided for @noFriendCategories.
  ///
  /// In ko, this message translates to:
  /// **'생성된 친구 카테고리가 없습니다. 먼저 카테고리를 생성해주세요.'**
  String get noFriendCategories;

  /// No description provided for @defaultCategoryCreated.
  ///
  /// In ko, this message translates to:
  /// **'기본 카테고리가 생성되었습니다'**
  String get defaultCategoryCreated;

  /// No description provided for @defaultCategoryFailed.
  ///
  /// In ko, this message translates to:
  /// **'기본 카테고리 생성에 실패했습니다'**
  String get defaultCategoryFailed;

  /// No description provided for @colorSelection.
  ///
  /// In ko, this message translates to:
  /// **'색상 선택'**
  String get colorSelection;

  /// No description provided for @iconSelection.
  ///
  /// In ko, this message translates to:
  /// **'아이콘 선택'**
  String get iconSelection;

  /// No description provided for @newHighlight.
  ///
  /// In ko, this message translates to:
  /// **'새 하이라이트'**
  String get newHighlight;

  /// No description provided for @updateAllPosts.
  ///
  /// In ko, this message translates to:
  /// **'모든 게시글 업데이트'**
  String get updateAllPosts;

  /// No description provided for @update.
  ///
  /// In ko, this message translates to:
  /// **'수정하기'**
  String get update;

  /// No description provided for @request.
  ///
  /// In ko, this message translates to:
  /// **'요청'**
  String get request;

  /// No description provided for @reviewRequest.
  ///
  /// In ko, this message translates to:
  /// **'리뷰 요청'**
  String get reviewRequest;

  /// No description provided for @reviewRequestSent.
  ///
  /// In ko, this message translates to:
  /// **'리뷰 요청이 전송되었습니다.'**
  String get reviewRequestSent;

  /// No description provided for @reviewRequestReject.
  ///
  /// In ko, this message translates to:
  /// **'리뷰 요청 거절'**
  String get reviewRequestReject;

  /// No description provided for @reviewConsensusDisabled.
  ///
  /// In ko, this message translates to:
  /// **'리뷰 합의 기능이 현재 비활성화되어 있습니다.'**
  String get reviewConsensusDisabled;

  /// No description provided for @featureUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'기능 사용 불가'**
  String get featureUnavailable;

  /// No description provided for @messageFeatureComingSoon.
  ///
  /// In ko, this message translates to:
  /// **'메시지 기능은 준비 중입니다.'**
  String get messageFeatureComingSoon;

  /// No description provided for @copyRules.
  ///
  /// In ko, this message translates to:
  /// **'규칙 복사'**
  String get copyRules;

  /// No description provided for @securityRulesCopied.
  ///
  /// In ko, this message translates to:
  /// **'보안 규칙이 클립보드에 복사되었습니다.'**
  String get securityRulesCopied;

  /// No description provided for @required.
  ///
  /// In ko, this message translates to:
  /// **'필수 입력 항목입니다'**
  String get required;

  /// No description provided for @invalidEmail.
  ///
  /// In ko, this message translates to:
  /// **'이메일 형식이 올바르지 않습니다'**
  String get invalidEmail;

  /// No description provided for @invalidPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호는 6자 이상이어야 합니다'**
  String get invalidPassword;

  /// No description provided for @passwordMismatch.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호가 일치하지 않습니다'**
  String get passwordMismatch;

  /// No description provided for @tooShort.
  ///
  /// In ko, this message translates to:
  /// **'너무 짧습니다'**
  String get tooShort;

  /// No description provided for @tooLong.
  ///
  /// In ko, this message translates to:
  /// **'너무 깁니다'**
  String get tooLong;

  /// No description provided for @accountInfo.
  ///
  /// In ko, this message translates to:
  /// **'계정 정보'**
  String get accountInfo;

  /// No description provided for @accountSecurity.
  ///
  /// In ko, this message translates to:
  /// **'계정 보안'**
  String get accountSecurity;

  /// No description provided for @legalInfo.
  ///
  /// In ko, this message translates to:
  /// **'법적 정보'**
  String get legalInfo;

  /// No description provided for @privacyProtection.
  ///
  /// In ko, this message translates to:
  /// **'개인정보 보호'**
  String get privacyProtection;

  /// No description provided for @openSourceLicenses.
  ///
  /// In ko, this message translates to:
  /// **'오픈소스 라이선스'**
  String get openSourceLicenses;

  /// No description provided for @manageGoogleAccount.
  ///
  /// In ko, this message translates to:
  /// **'Google 계정 관리'**
  String get manageGoogleAccount;

  /// No description provided for @selectCategoryRequired.
  ///
  /// In ko, this message translates to:
  /// **'카테고리 선택 (필수)'**
  String get selectCategoryRequired;

  /// No description provided for @selectedCount.
  ///
  /// In ko, this message translates to:
  /// **'개 선택됨'**
  String get selectedCount;

  /// No description provided for @enterSearchQuery.
  ///
  /// In ko, this message translates to:
  /// **'검색어를 입력하세요'**
  String get enterSearchQuery;

  /// No description provided for @description.
  ///
  /// In ko, this message translates to:
  /// **'설명'**
  String get description;

  /// No description provided for @korean.
  ///
  /// In ko, this message translates to:
  /// **'한국어'**
  String get korean;

  /// No description provided for @english.
  ///
  /// In ko, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @reauthenticateRequired.
  ///
  /// In ko, this message translates to:
  /// **'보안을 위해 다시 로그인이 필요합니다'**
  String get reauthenticateRequired;

  /// No description provided for @loginMethod.
  ///
  /// In ko, this message translates to:
  /// **'로그인 방식'**
  String get loginMethod;

  /// No description provided for @googleAccount.
  ///
  /// In ko, this message translates to:
  /// **'Google 계정'**
  String get googleAccount;

  /// No description provided for @emailPassword.
  ///
  /// In ko, this message translates to:
  /// **'이메일/비밀번호'**
  String get emailPassword;

  /// No description provided for @other.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get other;

  /// No description provided for @enterMeetupLocation.
  ///
  /// In ko, this message translates to:
  /// **'모임 장소를 입력하세요'**
  String get enterMeetupLocation;

  /// No description provided for @pleaseEnterLocation.
  ///
  /// In ko, this message translates to:
  /// **'장소를 입력해주세요'**
  String get pleaseEnterLocation;

  /// No description provided for @timeSelection.
  ///
  /// In ko, this message translates to:
  /// **'시간 선택'**
  String get timeSelection;

  /// No description provided for @undecided.
  ///
  /// In ko, this message translates to:
  /// **'미정'**
  String get undecided;

  /// No description provided for @todayTimePassed.
  ///
  /// In ko, this message translates to:
  /// **'오늘은 이미 지난 시간입니다. \'미정\'으로 모임을 생성하거나 다른 날짜를 선택해주세요.'**
  String get todayTimePassed;

  /// No description provided for @people.
  ///
  /// In ko, this message translates to:
  /// **'명'**
  String get people;

  /// No description provided for @selectFriendGroupsForMeetup.
  ///
  /// In ko, this message translates to:
  /// **'이 모임을 볼 수 있는 친구 그룹 선택'**
  String get selectFriendGroupsForMeetup;

  /// No description provided for @noGroupSelectedWarning.
  ///
  /// In ko, this message translates to:
  /// **'그룹을 선택하지 않으면 아무도 이 모임을 볼 수 없습니다'**
  String get noGroupSelectedWarning;

  /// No description provided for @thumbnailSettingsOptional.
  ///
  /// In ko, this message translates to:
  /// **'썸네일 설정 (선택사항)'**
  String get thumbnailSettingsOptional;

  /// No description provided for @thumbnailImage.
  ///
  /// In ko, this message translates to:
  /// **'썸네일 이미지'**
  String get thumbnailImage;

  /// No description provided for @attachImage.
  ///
  /// In ko, this message translates to:
  /// **'이미지 첨부'**
  String get attachImage;

  /// No description provided for @changeImage.
  ///
  /// In ko, this message translates to:
  /// **'이미지 변경'**
  String get changeImage;

  /// No description provided for @searchByFriendName.
  ///
  /// In ko, this message translates to:
  /// **'친구 이름으로 검색'**
  String get searchByFriendName;

  /// No description provided for @searchUsers.
  ///
  /// In ko, this message translates to:
  /// **'사용자를 검색해보세요'**
  String get searchUsers;

  /// No description provided for @searchByNicknameOrName.
  ///
  /// In ko, this message translates to:
  /// **'닉네임이나 이름으로 검색하여\n새로운 친구를 찾아보세요'**
  String get searchByNicknameOrName;

  /// No description provided for @searchAndAddFriends.
  ///
  /// In ko, this message translates to:
  /// **'사용자를 검색하여 친구를 추가해보세요'**
  String get searchAndAddFriends;

  /// No description provided for @receivedRequests.
  ///
  /// In ko, this message translates to:
  /// **'받은 요청'**
  String get receivedRequests;

  /// No description provided for @sentRequests.
  ///
  /// In ko, this message translates to:
  /// **'보낸 요청'**
  String get sentRequests;

  /// No description provided for @noReceivedRequests.
  ///
  /// In ko, this message translates to:
  /// **'받은 친구요청이 없습니다'**
  String get noReceivedRequests;

  /// No description provided for @newRequestsWillAppearHere.
  ///
  /// In ko, this message translates to:
  /// **'새로운 친구요청이 오면 여기에 표시됩니다'**
  String get newRequestsWillAppearHere;

  /// No description provided for @noSentRequests.
  ///
  /// In ko, this message translates to:
  /// **'보낸 친구요청이 없습니다'**
  String get noSentRequests;

  /// No description provided for @searchToSendRequest.
  ///
  /// In ko, this message translates to:
  /// **'사용자를 검색하여 친구요청을 보내보세요'**
  String get searchToSendRequest;

  /// No description provided for @friendCategoriesManagement.
  ///
  /// In ko, this message translates to:
  /// **'친구 카테고리 관리'**
  String get friendCategoriesManagement;

  /// No description provided for @noFriendGroupsYet.
  ///
  /// In ko, this message translates to:
  /// **'생성된 친구 그룹이 없습니다.\n친구 카테고리 관리에서 그룹을 만들어보세요.'**
  String get noFriendGroupsYet;

  /// No description provided for @friendsCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}명의 친구'**
  String friendsCount(Object count);

  /// No description provided for @noSearchResults.
  ///
  /// In ko, this message translates to:
  /// **'검색 결과가 없어요'**
  String get noSearchResults;

  /// No description provided for @blockList.
  ///
  /// In ko, this message translates to:
  /// **'차단 목록'**
  String get blockList;

  /// No description provided for @accountManagement.
  ///
  /// In ko, this message translates to:
  /// **'계정 관리'**
  String get accountManagement;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In ko, this message translates to:
  /// **'계정을 삭제하면 모든 데이터가 영구적으로 삭제됩니다. 정말 삭제하시겠습니까?'**
  String get deleteAccountWarning;

  /// No description provided for @notificationDeleted.
  ///
  /// In ko, this message translates to:
  /// **'알림이 삭제되었습니다'**
  String get notificationDeleted;

  /// No description provided for @daysAgo.
  ///
  /// In ko, this message translates to:
  /// **'{count, plural, =1{{count}일 전} other{{count}일 전}}'**
  String daysAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In ko, this message translates to:
  /// **'{count, plural, =1{{count}시간 전} other{{count}시간 전}}'**
  String hoursAgo(int count);

  /// No description provided for @minutesAgo.
  ///
  /// In ko, this message translates to:
  /// **'{count, plural, =1{{count}분 전} other{{count}분 전}}'**
  String minutesAgo(int count);

  /// No description provided for @justNow.
  ///
  /// In ko, this message translates to:
  /// **'방금 전'**
  String get justNow;

  /// No description provided for @markAllAsRead.
  ///
  /// In ko, this message translates to:
  /// **'모두 읽음'**
  String get markAllAsRead;

  /// No description provided for @notificationLoadError.
  ///
  /// In ko, this message translates to:
  /// **'알림을 불러오는 중 오류가 발생했습니다'**
  String get notificationLoadError;

  /// No description provided for @noNotifications.
  ///
  /// In ko, this message translates to:
  /// **'알림이 없습니다'**
  String get noNotifications;

  /// No description provided for @activityBoard.
  ///
  /// In ko, this message translates to:
  /// **'활동 게시판'**
  String get activityBoard;

  /// No description provided for @infoBoard.
  ///
  /// In ko, this message translates to:
  /// **'정보 게시판'**
  String get infoBoard;

  /// No description provided for @pleaseEnterSearchQuery.
  ///
  /// In ko, this message translates to:
  /// **'검색어를 입력해주세요'**
  String get pleaseEnterSearchQuery;

  /// No description provided for @tapToChangeImage.
  ///
  /// In ko, this message translates to:
  /// **'탭하여 이미지 변경'**
  String get tapToChangeImage;

  /// No description provided for @applyProfileToAllPosts.
  ///
  /// In ko, this message translates to:
  /// **'모든 게시글에 프로필 반영'**
  String get applyProfileToAllPosts;

  /// No description provided for @updating.
  ///
  /// In ko, this message translates to:
  /// **'업데이트 중...'**
  String get updating;

  /// No description provided for @postSaved.
  ///
  /// In ko, this message translates to:
  /// **'게시글이 저장되었습니다'**
  String get postSaved;

  /// No description provided for @postUnsaved.
  ///
  /// In ko, this message translates to:
  /// **'게시글 저장이 취소되었습니다'**
  String get postUnsaved;

  /// No description provided for @deletePostConfirm.
  ///
  /// In ko, this message translates to:
  /// **'정말 이 게시글을 삭제하시겠습니까?'**
  String get deletePostConfirm;

  /// No description provided for @commentSubmitFailed.
  ///
  /// In ko, this message translates to:
  /// **'댓글 등록에 실패했습니다.'**
  String get commentSubmitFailed;

  /// No description provided for @enterComment.
  ///
  /// In ko, this message translates to:
  /// **'Enter comment...'**
  String get enterComment;

  /// No description provided for @unsave.
  ///
  /// In ko, this message translates to:
  /// **'저장 취소'**
  String get unsave;

  /// No description provided for @savePost.
  ///
  /// In ko, this message translates to:
  /// **'게시글 저장'**
  String get savePost;

  /// No description provided for @deleteComment.
  ///
  /// In ko, this message translates to:
  /// **'댓글 삭제'**
  String get deleteComment;

  /// No description provided for @loginToComment.
  ///
  /// In ko, this message translates to:
  /// **'로그인 후 댓글을 작성할 수 있습니다'**
  String get loginToComment;

  /// No description provided for @today.
  ///
  /// In ko, this message translates to:
  /// **'오늘'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In ko, this message translates to:
  /// **'어제'**
  String get yesterday;

  /// No description provided for @thisWeek.
  ///
  /// In ko, this message translates to:
  /// **'이번 주'**
  String get thisWeek;

  /// No description provided for @previous.
  ///
  /// In ko, this message translates to:
  /// **'이전'**
  String get previous;

  /// No description provided for @selected.
  ///
  /// In ko, this message translates to:
  /// **'선택됨'**
  String get selected;

  /// No description provided for @select.
  ///
  /// In ko, this message translates to:
  /// **'선택'**
  String get select;

  /// No description provided for @scheduled.
  ///
  /// In ko, this message translates to:
  /// **'예정'**
  String get scheduled;

  /// No description provided for @dateAndTime.
  ///
  /// In ko, this message translates to:
  /// **'날짜 및 시각'**
  String get dateAndTime;

  /// No description provided for @venue.
  ///
  /// In ko, this message translates to:
  /// **'모임 장소'**
  String get venue;

  /// No description provided for @numberOfParticipants.
  ///
  /// In ko, this message translates to:
  /// **'참가 인원'**
  String get numberOfParticipants;

  /// No description provided for @organizer.
  ///
  /// In ko, this message translates to:
  /// **'주최자'**
  String get organizer;

  /// No description provided for @nationality.
  ///
  /// In ko, this message translates to:
  /// **'국적'**
  String get nationality;

  /// No description provided for @meetupDetails.
  ///
  /// In ko, this message translates to:
  /// **'모임 상세'**
  String get meetupDetails;

  /// No description provided for @cancelMeetupButton.
  ///
  /// In ko, this message translates to:
  /// **'모임 취소'**
  String get cancelMeetupButton;

  /// No description provided for @cancelMeetupFailed.
  ///
  /// In ko, this message translates to:
  /// **'모임 취소에 실패했습니다. 다시 시도해주세요.'**
  String get cancelMeetupFailed;

  /// No description provided for @peopleUnit.
  ///
  /// In ko, this message translates to:
  /// **'명'**
  String get peopleUnit;

  /// No description provided for @openStatus.
  ///
  /// In ko, this message translates to:
  /// **'모집중'**
  String get openStatus;

  /// No description provided for @closedStatus.
  ///
  /// In ko, this message translates to:
  /// **'마감'**
  String get closedStatus;

  /// No description provided for @meetupJoinFailed.
  ///
  /// In ko, this message translates to:
  /// **'모임 참여에 실패했습니다. 다시 시도해주세요.'**
  String get meetupJoinFailed;

  /// No description provided for @leaveMeetupFailed.
  ///
  /// In ko, this message translates to:
  /// **'참여 취소에 실패했습니다. 다시 시도해주세요.'**
  String get leaveMeetupFailed;

  /// No description provided for @reply.
  ///
  /// In ko, this message translates to:
  /// **'답글'**
  String get reply;

  /// No description provided for @replies.
  ///
  /// In ko, this message translates to:
  /// **'답글'**
  String get replies;

  /// No description provided for @replyToUser.
  ///
  /// In ko, this message translates to:
  /// **'님에게 답글...'**
  String get replyToUser;

  /// No description provided for @writeReply.
  ///
  /// In ko, this message translates to:
  /// **'답글 작성'**
  String get writeReply;

  /// No description provided for @hideReplies.
  ///
  /// In ko, this message translates to:
  /// **'숨기기'**
  String get hideReplies;

  /// No description provided for @showReplies.
  ///
  /// In ko, this message translates to:
  /// **'보기'**
  String get showReplies;

  /// No description provided for @replyCreated.
  ///
  /// In ko, this message translates to:
  /// **'답글이 등록되었습니다.'**
  String get replyCreated;

  /// No description provided for @replyCreateFailed.
  ///
  /// In ko, this message translates to:
  /// **'답글 등록에 실패했습니다.'**
  String get replyCreateFailed;

  /// No description provided for @repliesCount.
  ///
  /// In ko, this message translates to:
  /// **'답글 {count}개'**
  String repliesCount(int count);

  /// No description provided for @firstCommentPrompt.
  ///
  /// In ko, this message translates to:
  /// **'첫 번째 댓글을 남겨보세요!'**
  String get firstCommentPrompt;

  /// No description provided for @loadingComments.
  ///
  /// In ko, this message translates to:
  /// **'댓글을 불러오는 중 오류가 발생했습니다'**
  String get loadingComments;

  /// No description provided for @editCategory.
  ///
  /// In ko, this message translates to:
  /// **'카테고리 수정'**
  String get editCategory;

  /// No description provided for @newCategory.
  ///
  /// In ko, this message translates to:
  /// **'새 카테고리'**
  String get newCategory;

  /// No description provided for @categoryName.
  ///
  /// In ko, this message translates to:
  /// **'카테고리 이름'**
  String get categoryName;

  /// No description provided for @categoryNameHint.
  ///
  /// In ko, this message translates to:
  /// **'예: 대학 친구'**
  String get categoryNameHint;

  /// No description provided for @createFirstCategory.
  ///
  /// In ko, this message translates to:
  /// **'카테고리로 친구 관리하기'**
  String get createFirstCategory;

  /// No description provided for @createFirstCategoryDescription.
  ///
  /// In ko, this message translates to:
  /// **'카테고리를 만들어 친구들을 그룹으로 관리해보세요.\n학교, 직장, 취미 등 다양한 그룹을 만들 수 있습니다.'**
  String get createFirstCategoryDescription;

  /// No description provided for @editAction.
  ///
  /// In ko, this message translates to:
  /// **'수정'**
  String get editAction;

  /// No description provided for @viewProfile.
  ///
  /// In ko, this message translates to:
  /// **'프로필 보기'**
  String get viewProfile;

  /// No description provided for @removeFriendAction.
  ///
  /// In ko, this message translates to:
  /// **'친구 삭제'**
  String get removeFriendAction;

  /// No description provided for @blockAction.
  ///
  /// In ko, this message translates to:
  /// **'차단하기'**
  String get blockAction;

  /// No description provided for @groupSettingsFor.
  ///
  /// In ko, this message translates to:
  /// **'{name}님의 카테고리 설정'**
  String groupSettingsFor(String name);

  /// No description provided for @notInAnyGroup.
  ///
  /// In ko, this message translates to:
  /// **'특정 그룹에 속하지 않습니다'**
  String get notInAnyGroup;

  /// No description provided for @friendsInGroup.
  ///
  /// In ko, this message translates to:
  /// **'{count}명의 친구'**
  String friendsInGroup(int count);

  /// No description provided for @categoryCreated.
  ///
  /// In ko, this message translates to:
  /// **'카테고리가 생성되었습니다'**
  String get categoryCreated;

  /// No description provided for @categoryUpdated.
  ///
  /// In ko, this message translates to:
  /// **'카테고리가 수정되었습니다'**
  String get categoryUpdated;

  /// No description provided for @categoryDeleted.
  ///
  /// In ko, this message translates to:
  /// **'카테고리가 삭제되었습니다'**
  String get categoryDeleted;

  /// No description provided for @categoryCreateFailed.
  ///
  /// In ko, this message translates to:
  /// **'카테고리 생성에 실패했습니다'**
  String get categoryCreateFailed;

  /// No description provided for @categoryUpdateFailed.
  ///
  /// In ko, this message translates to:
  /// **'카테고리 수정에 실패했습니다'**
  String get categoryUpdateFailed;

  /// No description provided for @categoryDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'카테고리 삭제에 실패했습니다'**
  String get categoryDeleteFailed;

  /// No description provided for @enterCategoryName.
  ///
  /// In ko, this message translates to:
  /// **'카테고리 이름을 입력해주세요'**
  String get enterCategoryName;

  /// No description provided for @deleteCategory.
  ///
  /// In ko, this message translates to:
  /// **'카테고리 삭제'**
  String get deleteCategory;

  /// No description provided for @deleteCategoryConfirm.
  ///
  /// In ko, this message translates to:
  /// **'\'{name}\' 카테고리를 삭제하시겠습니까?\n\n이 카테고리에 속한 친구들은 다른 카테고리로 이동됩니다.'**
  String deleteCategoryConfirm(String name);

  /// No description provided for @unfriendConfirm.
  ///
  /// In ko, this message translates to:
  /// **'정말로 {name}님을 친구에서 삭제하시겠습니까?'**
  String unfriendConfirm(String name);

  /// No description provided for @unfriendSuccess.
  ///
  /// In ko, this message translates to:
  /// **'친구를 삭제했습니다'**
  String get unfriendSuccess;

  /// No description provided for @unfriendFailed.
  ///
  /// In ko, this message translates to:
  /// **'친구 삭제에 실패했습니다'**
  String get unfriendFailed;

  /// No description provided for @blockUserConfirm.
  ///
  /// In ko, this message translates to:
  /// **'정말로 {name}님을 차단하시겠습니까?\n차단된 사용자는 더 이상 친구요청을 보낼 수 없습니다.'**
  String blockUserConfirm(String name);

  /// No description provided for @userBlockedSuccess.
  ///
  /// In ko, this message translates to:
  /// **'사용자를 차단했습니다'**
  String get userBlockedSuccess;

  /// No description provided for @userBlockFailed.
  ///
  /// In ko, this message translates to:
  /// **'사용자 차단에 실패했습니다'**
  String get userBlockFailed;

  /// No description provided for @cannotLoadProfile.
  ///
  /// In ko, this message translates to:
  /// **'프로필을 불러올 수 없습니다'**
  String get cannotLoadProfile;

  /// No description provided for @groupAssignmentFailed.
  ///
  /// In ko, this message translates to:
  /// **'그룹 설정에 실패했습니다. 다시 시도해주세요'**
  String get groupAssignmentFailed;

  /// No description provided for @removedFromAllGroups.
  ///
  /// In ko, this message translates to:
  /// **'{name}님을 모든 그룹에서 제거했습니다'**
  String removedFromAllGroups(String name);

  /// No description provided for @addedToGroup.
  ///
  /// In ko, this message translates to:
  /// **'{name}님을 \"{group}\" 그룹에 추가했습니다'**
  String addedToGroup(String name, String group);

  /// No description provided for @errorOccurred.
  ///
  /// In ko, this message translates to:
  /// **'오류가 발생했습니다. 다시 시도해주세요'**
  String get errorOccurred;

  /// No description provided for @friendStatus.
  ///
  /// In ko, this message translates to:
  /// **'친구'**
  String get friendStatus;

  /// No description provided for @addCategory.
  ///
  /// In ko, this message translates to:
  /// **'카테고리 추가'**
  String get addCategory;

  /// No description provided for @newCategoryCreate.
  ///
  /// In ko, this message translates to:
  /// **'첫 카테고리 만들기'**
  String get newCategoryCreate;

  /// No description provided for @participatedReviews.
  ///
  /// In ko, this message translates to:
  /// **'참여한 후기'**
  String get participatedReviews;

  /// No description provided for @user.
  ///
  /// In ko, this message translates to:
  /// **'사용자'**
  String get user;

  /// No description provided for @cannotLoadReviews.
  ///
  /// In ko, this message translates to:
  /// **'후기를 불러올 수 없습니다'**
  String get cannotLoadReviews;

  /// No description provided for @noReviewsYet.
  ///
  /// In ko, this message translates to:
  /// **'아직 작성한 후기가 없습니다'**
  String get noReviewsYet;

  /// No description provided for @joinMeetupAndWriteReview.
  ///
  /// In ko, this message translates to:
  /// **'모임에 참여하고 후기를 작성해보세요!'**
  String get joinMeetupAndWriteReview;

  /// No description provided for @reviewDetail.
  ///
  /// In ko, this message translates to:
  /// **'후기'**
  String get reviewDetail;

  /// No description provided for @rating.
  ///
  /// In ko, this message translates to:
  /// **'평점'**
  String get rating;

  /// No description provided for @loginToViewReviews.
  ///
  /// In ko, this message translates to:
  /// **'후기를 보려면 로그인해주세요'**
  String get loginToViewReviews;

  /// No description provided for @noSavedPosts.
  ///
  /// In ko, this message translates to:
  /// **'저장된 게시물이 없습니다'**
  String get noSavedPosts;

  /// No description provided for @saveInterestingPosts.
  ///
  /// In ko, this message translates to:
  /// **'관심 있는 게시물을 저장해보세요'**
  String get saveInterestingPosts;

  /// No description provided for @loginToViewSavedPosts.
  ///
  /// In ko, this message translates to:
  /// **'저장된 게시물을 보려면 로그인해주세요'**
  String get loginToViewSavedPosts;

  /// No description provided for @dayAgo.
  ///
  /// In ko, this message translates to:
  /// **'일 전'**
  String get dayAgo;

  /// No description provided for @daysAgoCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}일 전'**
  String daysAgoCount(int count);

  /// No description provided for @hourAgo.
  ///
  /// In ko, this message translates to:
  /// **'시간 전'**
  String get hourAgo;

  /// No description provided for @hoursAgoCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}시간 전'**
  String hoursAgoCount(int count);

  /// No description provided for @minuteAgo.
  ///
  /// In ko, this message translates to:
  /// **'분 전'**
  String get minuteAgo;

  /// No description provided for @minutesAgoCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}분 전'**
  String minutesAgoCount(int count);

  /// No description provided for @justNowTime.
  ///
  /// In ko, this message translates to:
  /// **'방금 전'**
  String get justNowTime;

  /// No description provided for @findFriends.
  ///
  /// In ko, this message translates to:
  /// **'함께할 친구를 찾아보세요'**
  String get findFriends;

  /// No description provided for @makeFriendsWithSameInterests.
  ///
  /// In ko, this message translates to:
  /// **'새로운 친구들과 즐거운 추억을 만들어보세요.\n같은 관심사를 가진 사람들이 기다리고 있어요.'**
  String get makeFriendsWithSameInterests;

  /// No description provided for @findFriendsAction.
  ///
  /// In ko, this message translates to:
  /// **'친구 찾기'**
  String get findFriendsAction;

  /// No description provided for @viewRecommendedFriends.
  ///
  /// In ko, this message translates to:
  /// **'추천 친구 보기'**
  String get viewRecommendedFriends;

  /// No description provided for @tryDifferentKeyword.
  ///
  /// In ko, this message translates to:
  /// **'다른 검색어를 시도해보세요'**
  String get tryDifferentKeyword;

  /// No description provided for @clearSearchQuery.
  ///
  /// In ko, this message translates to:
  /// **'검색어 지우기'**
  String get clearSearchQuery;

  /// No description provided for @friendRequestSent.
  ///
  /// In ko, this message translates to:
  /// **'친구요청을 보냈습니다'**
  String get friendRequestSent;

  /// No description provided for @friendRequestFailed.
  ///
  /// In ko, this message translates to:
  /// **'친구요청 전송에 실패했습니다'**
  String get friendRequestFailed;

  /// No description provided for @friendRequestCancelled.
  ///
  /// In ko, this message translates to:
  /// **'친구요청을 취소했습니다'**
  String get friendRequestCancelled;

  /// No description provided for @friendRequestCancelFailed.
  ///
  /// In ko, this message translates to:
  /// **'친구요청 취소에 실패했습니다'**
  String get friendRequestCancelFailed;

  /// No description provided for @unfriendedUser.
  ///
  /// In ko, this message translates to:
  /// **'친구를 삭제했습니다'**
  String get unfriendedUser;

  /// No description provided for @userUnblocked.
  ///
  /// In ko, this message translates to:
  /// **'사용자 차단을 해제했습니다'**
  String get userUnblocked;

  /// No description provided for @unblockFailed.
  ///
  /// In ko, this message translates to:
  /// **'차단 해제에 실패했습니다'**
  String get unblockFailed;

  /// No description provided for @noResultsFound.
  ///
  /// In ko, this message translates to:
  /// **'검색 결과가 없습니다'**
  String get noResultsFound;

  /// No description provided for @tryDifferentSearch.
  ///
  /// In ko, this message translates to:
  /// **'다른 검색어를 시도해보세요'**
  String get tryDifferentSearch;

  /// No description provided for @confirmUnfriend.
  ///
  /// In ko, this message translates to:
  /// **'정말로 이 사용자를 친구에서 삭제하시겠습니까?'**
  String get confirmUnfriend;

  /// No description provided for @blockUserDescription.
  ///
  /// In ko, this message translates to:
  /// **'정말로 이 사용자를 차단하시겠습니까?\n차단된 사용자는 더 이상 친구요청을 보낼 수 없습니다.'**
  String get blockUserDescription;

  /// No description provided for @unblockUser.
  ///
  /// In ko, this message translates to:
  /// **'차단 해제'**
  String get unblockUser;

  /// No description provided for @confirmUnblock.
  ///
  /// In ko, this message translates to:
  /// **'정말로 이 사용자의 차단을 해제하시겠습니까?'**
  String get confirmUnblock;

  /// No description provided for @meetupFilter.
  ///
  /// In ko, this message translates to:
  /// **'모임 필터'**
  String get meetupFilter;

  /// No description provided for @publicMeetupsOnly.
  ///
  /// In ko, this message translates to:
  /// **'전체 공개만'**
  String get publicMeetupsOnly;

  /// No description provided for @showOnlyPublicMeetups.
  ///
  /// In ko, this message translates to:
  /// **'누구나 볼 수 있도록 공개된 모임만 표시'**
  String get showOnlyPublicMeetups;

  /// No description provided for @friendsMeetupsOnly.
  ///
  /// In ko, this message translates to:
  /// **'친구 모임만'**
  String get friendsMeetupsOnly;

  /// No description provided for @showAllFriendsMeetups.
  ///
  /// In ko, this message translates to:
  /// **'친구들이 만든 모든 모임을 표시'**
  String get showAllFriendsMeetups;

  /// No description provided for @viewSpecificFriendGroup.
  ///
  /// In ko, this message translates to:
  /// **'특정 친구 그룹만 보기'**
  String get viewSpecificFriendGroup;

  /// No description provided for @showSelectedGroupMeetups.
  ///
  /// In ko, this message translates to:
  /// **'선택한 그룹에 공개된 모임만 표시됩니다'**
  String get showSelectedGroupMeetups;

  /// No description provided for @friendsCountInGroup.
  ///
  /// In ko, this message translates to:
  /// **'{count}명의 친구 · 이 그룹에 공개된 모임만 표시'**
  String friendsCountInGroup(int count);

  /// No description provided for @friendRequestAccepted.
  ///
  /// In ko, this message translates to:
  /// **'친구요청을 수락했습니다'**
  String get friendRequestAccepted;

  /// No description provided for @friendRequestAcceptFailed.
  ///
  /// In ko, this message translates to:
  /// **'친구요청 수락에 실패했습니다'**
  String get friendRequestAcceptFailed;

  /// No description provided for @rejectFriendRequest.
  ///
  /// In ko, this message translates to:
  /// **'친구요청 거절'**
  String get rejectFriendRequest;

  /// No description provided for @confirmRejectFriendRequest.
  ///
  /// In ko, this message translates to:
  /// **'정말로 이 친구요청을 거절하시겠습니까?'**
  String get confirmRejectFriendRequest;

  /// No description provided for @friendRequestRejected.
  ///
  /// In ko, this message translates to:
  /// **'친구요청을 거절했습니다'**
  String get friendRequestRejected;

  /// No description provided for @friendRequestRejectFailed.
  ///
  /// In ko, this message translates to:
  /// **'친구요청 거절에 실패했습니다'**
  String get friendRequestRejectFailed;

  /// No description provided for @cancelFriendRequest.
  ///
  /// In ko, this message translates to:
  /// **'친구요청 취소'**
  String get cancelFriendRequest;

  /// No description provided for @confirmCancelFriendRequest.
  ///
  /// In ko, this message translates to:
  /// **'정말로 이 친구요청을 취소하시겠습니까?'**
  String get confirmCancelFriendRequest;

  /// No description provided for @friendRequestCancelledSuccess.
  ///
  /// In ko, this message translates to:
  /// **'친구요청을 취소했습니다'**
  String get friendRequestCancelledSuccess;

  /// No description provided for @cancelAction.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get cancelAction;

  /// No description provided for @pleaseEnterMeetupTitle.
  ///
  /// In ko, this message translates to:
  /// **'모임 제목을 입력해주세요'**
  String get pleaseEnterMeetupTitle;

  /// No description provided for @pleaseEnterMeetupDescription.
  ///
  /// In ko, this message translates to:
  /// **'모임 설명을 입력해주세요'**
  String get pleaseEnterMeetupDescription;

  /// No description provided for @meetupIsFull.
  ///
  /// In ko, this message translates to:
  /// **'모임 정원이 다 찼습니다'**
  String get meetupIsFull;

  /// No description provided for @meetupIsFullMessage.
  ///
  /// In ko, this message translates to:
  /// **'{meetupTitle} 모임의 정원({maxParticipants}명)이 모두 채워졌습니다.'**
  String meetupIsFullMessage(String meetupTitle, int maxParticipants);

  /// No description provided for @meetupCancelledMessage.
  ///
  /// In ko, this message translates to:
  /// **'참여 예정이던 \"{meetupTitle}\" 모임이 취소되었습니다.'**
  String meetupCancelledMessage(String meetupTitle);

  /// No description provided for @newCommentAdded.
  ///
  /// In ko, this message translates to:
  /// **'새 댓글이 달렸습니다'**
  String get newCommentAdded;

  /// No description provided for @newCommentMessage.
  ///
  /// In ko, this message translates to:
  /// **'{commenterName}님이 회원님의 게시글 \"{postTitle}\"에 댓글을 남겼습니다.'**
  String newCommentMessage(String commenterName, String postTitle);

  /// No description provided for @newLikeAdded.
  ///
  /// In ko, this message translates to:
  /// **'게시글에 좋아요가 추가되었습니다'**
  String get newLikeAdded;

  /// No description provided for @newLikeMessage.
  ///
  /// In ko, this message translates to:
  /// **'{likerName}님이 회원님의 게시글 \"{postTitle}\"을 좋아합니다.'**
  String newLikeMessage(String likerName, String postTitle);

  /// No description provided for @newParticipantJoined.
  ///
  /// In ko, this message translates to:
  /// **'새로운 참여자'**
  String get newParticipantJoined;

  /// No description provided for @newParticipantJoinedMessage.
  ///
  /// In ko, this message translates to:
  /// **'{name}님이 회원님의 모임 \"{meetupTitle}\"에 참여했습니다.'**
  String newParticipantJoinedMessage(String name, String meetupTitle);

  /// No description provided for @newCommentLikeMessage.
  ///
  /// In ko, this message translates to:
  /// **'{likerName}님이 회원님의 댓글을 좋아합니다.'**
  String newCommentLikeMessage(String likerName);

  /// No description provided for @friendRequestMessage.
  ///
  /// In ko, this message translates to:
  /// **'{name}님이 친구요청을 보냈습니다'**
  String friendRequestMessage(String name);

  /// No description provided for @emailSignup.
  ///
  /// In ko, this message translates to:
  /// **'이메일 회원가입'**
  String get emailSignup;

  /// No description provided for @emailLogin.
  ///
  /// In ko, this message translates to:
  /// **'이메일 로그인'**
  String get emailLogin;

  /// No description provided for @hanyangEmailOnly.
  ///
  /// In ko, this message translates to:
  /// **'한양대학교 이메일 인증'**
  String get hanyangEmailOnly;

  /// No description provided for @hanyangEmailLogin.
  ///
  /// In ko, this message translates to:
  /// **'한양대학교 이메일로 로그인'**
  String get hanyangEmailLogin;

  /// No description provided for @hanyangEmailDescription.
  ///
  /// In ko, this message translates to:
  /// **'회원가입을 위해 한양대학교 이메일 인증이 필요합니다.\n인증 후 Google 계정으로 로그인할 수 있습니다.'**
  String get hanyangEmailDescription;

  /// No description provided for @sendVerificationCode.
  ///
  /// In ko, this message translates to:
  /// **'인증번호 전송'**
  String get sendVerificationCode;

  /// No description provided for @verificationCode.
  ///
  /// In ko, this message translates to:
  /// **'인증번호'**
  String get verificationCode;

  /// No description provided for @verifyCode.
  ///
  /// In ko, this message translates to:
  /// **'인증 확인'**
  String get verifyCode;

  /// No description provided for @emailVerified.
  ///
  /// In ko, this message translates to:
  /// **'이메일 인증이 완료되었습니다'**
  String get emailVerified;

  /// No description provided for @verificationCodeSent.
  ///
  /// In ko, this message translates to:
  /// **'인증번호가 이메일로 전송되었습니다'**
  String get verificationCodeSent;

  /// No description provided for @verificationCodeExpired.
  ///
  /// In ko, this message translates to:
  /// **'인증번호가 만료되었습니다. 다시 요청해주세요.'**
  String get verificationCodeExpired;

  /// No description provided for @verificationCodeInvalid.
  ///
  /// In ko, this message translates to:
  /// **'인증번호가 일치하지 않습니다. 다시 확인해주세요.'**
  String get verificationCodeInvalid;

  /// No description provided for @verificationCodeAttemptsExceeded.
  ///
  /// In ko, this message translates to:
  /// **'인증번호 입력 횟수를 초과했습니다. 다시 요청해주세요.'**
  String get verificationCodeAttemptsExceeded;

  /// No description provided for @emailVerificationRequired.
  ///
  /// In ko, this message translates to:
  /// **'한양메일 인증'**
  String get emailVerificationRequired;

  /// No description provided for @signupWithEmail.
  ///
  /// In ko, this message translates to:
  /// **'이메일로 회원가입'**
  String get signupWithEmail;

  /// No description provided for @loginWithEmail.
  ///
  /// In ko, this message translates to:
  /// **'이메일로 로그인'**
  String get loginWithEmail;

  /// No description provided for @hanyangEmailRequired.
  ///
  /// In ko, this message translates to:
  /// **'한양대학교 이메일 주소만 사용할 수 있습니다'**
  String get hanyangEmailRequired;

  /// No description provided for @emailFormatInvalid.
  ///
  /// In ko, this message translates to:
  /// **'올바른 이메일 형식이 아닙니다'**
  String get emailFormatInvalid;

  /// No description provided for @verificationCodeRequired.
  ///
  /// In ko, this message translates to:
  /// **'인증번호를 입력해주세요'**
  String get verificationCodeRequired;

  /// No description provided for @verificationCodeLength.
  ///
  /// In ko, this message translates to:
  /// **'4자리 인증번호를 입력해주세요'**
  String get verificationCodeLength;

  /// No description provided for @passwordRequired.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 입력해주세요'**
  String get passwordRequired;

  /// No description provided for @passwordMinLength.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호는 6자 이상이어야 합니다'**
  String get passwordMinLength;

  /// No description provided for @signupSuccess.
  ///
  /// In ko, this message translates to:
  /// **'회원가입이 완료되었습니다'**
  String get signupSuccess;

  /// No description provided for @signupFailed.
  ///
  /// In ko, this message translates to:
  /// **'회원가입에 실패했습니다. 다시 시도해주세요.'**
  String get signupFailed;

  /// No description provided for @noAccountYet.
  ///
  /// In ko, this message translates to:
  /// **'아직 계정이 없으신가요?'**
  String get noAccountYet;

  /// No description provided for @helpTitle.
  ///
  /// In ko, this message translates to:
  /// **'도움말'**
  String get helpTitle;

  /// No description provided for @helpContent.
  ///
  /// In ko, this message translates to:
  /// **'• 한양대학교 이메일 주소만 사용할 수 있습니다\n• 비밀번호를 잊으셨다면 학교 이메일 시스템을 이용해주세요\n• 계정 관련 문의: hanyangwatson@gmail.com'**
  String get helpContent;

  /// No description provided for @or.
  ///
  /// In ko, this message translates to:
  /// **'또는'**
  String get or;

  /// No description provided for @appName.
  ///
  /// In ko, this message translates to:
  /// **'Wefilling'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In ko, this message translates to:
  /// **'함께하는 커뮤니티'**
  String get appTagline;

  /// No description provided for @welcomeTitle.
  ///
  /// In ko, this message translates to:
  /// **'환영합니다!'**
  String get welcomeTitle;

  /// No description provided for @googleLoginDescription.
  ///
  /// In ko, this message translates to:
  /// **'구글 계정으로 로그인하고\n다양한 기능을 이용해 보세요.'**
  String get googleLoginDescription;

  /// No description provided for @googleLogin.
  ///
  /// In ko, this message translates to:
  /// **'구글 계정으로 로그인'**
  String get googleLogin;

  /// No description provided for @loggingIn.
  ///
  /// In ko, this message translates to:
  /// **'로그인 중...'**
  String get loggingIn;

  /// No description provided for @loginTermsNotice.
  ///
  /// In ko, this message translates to:
  /// **'로그인하면 서비스 이용약관 및 개인정보 보호정책에 동의하게 됩니다.'**
  String get loginTermsNotice;

  /// No description provided for @verificationSuccess.
  ///
  /// In ko, this message translates to:
  /// **'인증 성공'**
  String get verificationSuccess;

  /// No description provided for @proceedWithGoogleLogin.
  ///
  /// In ko, this message translates to:
  /// **'인증이 완료되었습니다.\nGoogle 계정으로 회원가입을 계속하시겠습니까?'**
  String get proceedWithGoogleLogin;

  /// No description provided for @continueWithGoogle.
  ///
  /// In ko, this message translates to:
  /// **'Google 계정으로 계속하기'**
  String get continueWithGoogle;

  /// No description provided for @appleLogin.
  ///
  /// In ko, this message translates to:
  /// **'Apple로 로그인'**
  String get appleLogin;

  /// No description provided for @continueWithApple.
  ///
  /// In ko, this message translates to:
  /// **'Apple로 계속하기'**
  String get continueWithApple;

  /// No description provided for @chooseLoginMethod.
  ///
  /// In ko, this message translates to:
  /// **'로그인 방법을 선택해주세요'**
  String get chooseLoginMethod;

  /// No description provided for @hanyangEmailAlreadyUsed.
  ///
  /// In ko, this message translates to:
  /// **'이미 사용된 한양메일입니다. 다른 메일을 사용해주세요.'**
  String get hanyangEmailAlreadyUsed;

  /// No description provided for @signupRequired.
  ///
  /// In ko, this message translates to:
  /// **'회원가입이 필요합니다.\n\n신규 사용자이거나 탈퇴한 계정인 경우 \'회원가입하기\' 버튼을 눌러 한양메일 인증을 진행해주세요.'**
  String get signupRequired;

  /// No description provided for @meetupNotifications.
  ///
  /// In ko, this message translates to:
  /// **'모임 알림'**
  String get meetupNotifications;

  /// No description provided for @postNotifications.
  ///
  /// In ko, this message translates to:
  /// **'게시글 알림'**
  String get postNotifications;

  /// No description provided for @generalSettings.
  ///
  /// In ko, this message translates to:
  /// **'전체 설정'**
  String get generalSettings;

  /// No description provided for @friendNotifications.
  ///
  /// In ko, this message translates to:
  /// **'친구 알림'**
  String get friendNotifications;

  /// No description provided for @privatePostAlertTitle.
  ///
  /// In ko, this message translates to:
  /// **'비공개 게시글 알림'**
  String get privatePostAlertTitle;

  /// No description provided for @privatePostAlertSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'허용된 사용자에게만 공개된 게시글 알림'**
  String get privatePostAlertSubtitle;

  /// No description provided for @meetupFullAlertTitle.
  ///
  /// In ko, this message translates to:
  /// **'모임 정원 마감 알림'**
  String get meetupFullAlertTitle;

  /// No description provided for @meetupFullAlertSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'내가 주최한 모임의 정원이 마감되면 알림'**
  String get meetupFullAlertSubtitle;

  /// No description provided for @meetupCancelledAlertTitle.
  ///
  /// In ko, this message translates to:
  /// **'모임 취소 알림'**
  String get meetupCancelledAlertTitle;

  /// No description provided for @meetupCancelledAlertSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'참여 신청한 모임이 취소되면 알림'**
  String get meetupCancelledAlertSubtitle;

  /// No description provided for @friendRequestAlertTitle.
  ///
  /// In ko, this message translates to:
  /// **'친구요청 알림'**
  String get friendRequestAlertTitle;

  /// No description provided for @friendRequestAlertSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'새로운 친구요청이 도착하면 알림'**
  String get friendRequestAlertSubtitle;

  /// No description provided for @commentAlertTitle.
  ///
  /// In ko, this message translates to:
  /// **'댓글 알림'**
  String get commentAlertTitle;

  /// No description provided for @commentAlertSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'내 게시글에 댓글이 작성되면 알림'**
  String get commentAlertSubtitle;

  /// No description provided for @likeAlertTitle.
  ///
  /// In ko, this message translates to:
  /// **'좋아요 알림'**
  String get likeAlertTitle;

  /// No description provided for @likeAlertSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'내 게시글에 좋아요가 추가되면 알림'**
  String get likeAlertSubtitle;

  /// No description provided for @allNotifications.
  ///
  /// In ko, this message translates to:
  /// **'모든 알림'**
  String get allNotifications;

  /// No description provided for @allNotificationsSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'모든 알림 활성화/비활성화'**
  String get allNotificationsSubtitle;

  /// No description provided for @adUpdatesTitle.
  ///
  /// In ko, this message translates to:
  /// **'광고 업데이트'**
  String get adUpdatesTitle;

  /// No description provided for @adUpdatesSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'새 광고/배너가 업데이트되면 알림'**
  String get adUpdatesSubtitle;

  /// No description provided for @loadSettingsError.
  ///
  /// In ko, this message translates to:
  /// **'설정을 불러오는 중 오류가 발생했습니다: {error}'**
  String loadSettingsError(String error);

  /// No description provided for @saveSettingsError.
  ///
  /// In ko, this message translates to:
  /// **'설정을 저장하는 중 오류가 발생했습니다: {error}'**
  String saveSettingsError(String error);

  /// No description provided for @hostedMeetupsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'주최한 모임이 없습니다\n새로운 모임을 만들어보세요!'**
  String get hostedMeetupsEmpty;

  /// No description provided for @joinedMeetupsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'참여했던 모임이 없습니다\n다른 사용자의 모임에 참여해보세요!'**
  String get joinedMeetupsEmpty;

  /// No description provided for @meetupLoadError.
  ///
  /// In ko, this message translates to:
  /// **'모임 정보를 불러오는 중 오류가 발생했습니다'**
  String get meetupLoadError;

  /// No description provided for @fullShort.
  ///
  /// In ko, this message translates to:
  /// **'마감'**
  String get fullShort;

  /// No description provided for @closed.
  ///
  /// In ko, this message translates to:
  /// **'종료'**
  String get closed;

  /// No description provided for @totalPostsCount.
  ///
  /// In ko, this message translates to:
  /// **'총 {count}개의 게시글'**
  String totalPostsCount(int count);

  /// No description provided for @noWrittenPosts.
  ///
  /// In ko, this message translates to:
  /// **'작성한 게시글이 없습니다'**
  String get noWrittenPosts;

  /// No description provided for @notificationDataMissing.
  ///
  /// In ko, this message translates to:
  /// **'알림 정보가 누락되었습니다'**
  String get notificationDataMissing;

  /// No description provided for @meetupNotFound.
  ///
  /// In ko, this message translates to:
  /// **'해당 모임을 찾을 수 없습니다'**
  String get meetupNotFound;

  /// No description provided for @postNotFound.
  ///
  /// In ko, this message translates to:
  /// **'해당 게시글을 찾을 수 없습니다'**
  String get postNotFound;

  /// No description provided for @commentLikeFailed.
  ///
  /// In ko, this message translates to:
  /// **'좋아요 업데이트에 실패했습니다'**
  String get commentLikeFailed;

  /// No description provided for @reviewWriteTitle.
  ///
  /// In ko, this message translates to:
  /// **'모임 후기 쓰기'**
  String get reviewWriteTitle;

  /// No description provided for @reviewEditTitle.
  ///
  /// In ko, this message translates to:
  /// **'후기 수정'**
  String get reviewEditTitle;

  /// No description provided for @reviewPhoto.
  ///
  /// In ko, this message translates to:
  /// **'후기 사진'**
  String get reviewPhoto;

  /// No description provided for @pickPhoto.
  ///
  /// In ko, this message translates to:
  /// **'사진 선택'**
  String get pickPhoto;

  /// No description provided for @imagePickFailed.
  ///
  /// In ko, this message translates to:
  /// **'이미지를 선택할 수 없습니다'**
  String get imagePickFailed;

  /// No description provided for @imageUploadFailed.
  ///
  /// In ko, this message translates to:
  /// **'이미지 업로드에 실패했습니다'**
  String get imageUploadFailed;

  /// No description provided for @pleaseSelectPhoto.
  ///
  /// In ko, this message translates to:
  /// **'사진을 선택해주세요'**
  String get pleaseSelectPhoto;

  /// No description provided for @pleaseEnterReviewContent.
  ///
  /// In ko, this message translates to:
  /// **'후기 내용을 입력해주세요'**
  String get pleaseEnterReviewContent;

  /// No description provided for @reviewUpdated.
  ///
  /// In ko, this message translates to:
  /// **'후기가 수정되었습니다'**
  String get reviewUpdated;

  /// No description provided for @reviewUpdateFailed.
  ///
  /// In ko, this message translates to:
  /// **'후기 수정에 실패했습니다'**
  String get reviewUpdateFailed;

  /// No description provided for @reviewCreateFailed.
  ///
  /// In ko, this message translates to:
  /// **'후기 생성에 실패했습니다'**
  String get reviewCreateFailed;

  /// No description provided for @reviewCreatedAndRequestsSent.
  ///
  /// In ko, this message translates to:
  /// **'후기가 작성되었으며 {count}명의 참여자에게 요청이 전송되었습니다'**
  String reviewCreatedAndRequestsSent(int count);

  /// No description provided for @reviewCreatedButNotificationFailed.
  ///
  /// In ko, this message translates to:
  /// **'후기는 작성되었지만 알림 전송에 실패했습니다'**
  String get reviewCreatedButNotificationFailed;

  /// No description provided for @reviewRequestInfo.
  ///
  /// In ko, this message translates to:
  /// **'참여자들에게 후기 수락 요청이 전송됩니다. 수락한 참여자의 프로필에 동일한 후기가 게시됩니다.'**
  String get reviewRequestInfo;

  /// No description provided for @reviewApprovalRequest.
  ///
  /// In ko, this message translates to:
  /// **'후기 수락 요청'**
  String get reviewApprovalRequest;

  /// No description provided for @reviewApprovalInfo.
  ///
  /// In ko, this message translates to:
  /// **'수락하면 이 후기가 내 프로필의 후기 섹션에 게시됩니다. 거절하면 내 프로필에는 게시되지 않습니다.'**
  String get reviewApprovalInfo;

  /// No description provided for @reviewAccepted.
  ///
  /// In ko, this message translates to:
  /// **'후기를 수락했습니다'**
  String get reviewAccepted;

  /// No description provided for @reviewRejected.
  ///
  /// In ko, this message translates to:
  /// **'후기를 거절했습니다'**
  String get reviewRejected;

  /// No description provided for @reviewApprovalRequestTitle.
  ///
  /// In ko, this message translates to:
  /// **'모임 후기 수락 요청'**
  String get reviewApprovalRequestTitle;

  /// No description provided for @reviewReject.
  ///
  /// In ko, this message translates to:
  /// **'거절'**
  String get reviewReject;

  /// No description provided for @reviewAccept.
  ///
  /// In ko, this message translates to:
  /// **'수락'**
  String get reviewAccept;

  /// No description provided for @reviewApprovalProcessError.
  ///
  /// In ko, this message translates to:
  /// **'처리 중 오류가 발생했습니다'**
  String get reviewApprovalProcessError;

  /// No description provided for @reviewProcessError.
  ///
  /// In ko, this message translates to:
  /// **'처리 중 오류가 발생했습니다'**
  String get reviewProcessError;

  /// No description provided for @reviewInfoMissing.
  ///
  /// In ko, this message translates to:
  /// **'후기 정보를 찾을 수 없습니다'**
  String get reviewInfoMissing;

  /// No description provided for @reviewInfoNotFound.
  ///
  /// In ko, this message translates to:
  /// **'후기 정보를 찾을 수 없습니다'**
  String get reviewInfoNotFound;

  /// No description provided for @reviewContent.
  ///
  /// In ko, this message translates to:
  /// **'후기 내용'**
  String get reviewContent;

  /// No description provided for @reviewWriteHint.
  ///
  /// In ko, this message translates to:
  /// **'모임 후기를 작성해주세요...'**
  String get reviewWriteHint;

  /// No description provided for @requestReviewAcceptance.
  ///
  /// In ko, this message translates to:
  /// **'후기 수락 요청'**
  String get requestReviewAcceptance;

  /// No description provided for @writeMeetupReview.
  ///
  /// In ko, this message translates to:
  /// **'모임 후기 쓰기'**
  String get writeMeetupReview;

  /// No description provided for @editReview.
  ///
  /// In ko, this message translates to:
  /// **'후기 수정'**
  String get editReview;

  /// No description provided for @deleteReview.
  ///
  /// In ko, this message translates to:
  /// **'후기 삭제'**
  String get deleteReview;

  /// No description provided for @completeOrCancelMeetup.
  ///
  /// In ko, this message translates to:
  /// **'모임 완료 / 취소'**
  String get completeOrCancelMeetup;

  /// No description provided for @meetupCompleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'모임 완료'**
  String get meetupCompleteTitle;

  /// No description provided for @meetupCompleteMessage.
  ///
  /// In ko, this message translates to:
  /// **'모임이 마감되었습니다. 모임을 완료 처리하시겠습니까?\n\n완료 처리하면 후기를 작성할 수 있습니다.'**
  String get meetupCompleteMessage;

  /// No description provided for @markAsCompleted.
  ///
  /// In ko, this message translates to:
  /// **'완료 처리'**
  String get markAsCompleted;

  /// No description provided for @meetupMarkedCompleted.
  ///
  /// In ko, this message translates to:
  /// **'모임이 완료 처리되었습니다'**
  String get meetupMarkedCompleted;

  /// No description provided for @meetupMarkCompleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'모임 완료 처리에 실패했습니다'**
  String get meetupMarkCompleteFailed;

  /// No description provided for @reviewNotFound.
  ///
  /// In ko, this message translates to:
  /// **'후기를 찾을 수 없습니다'**
  String get reviewNotFound;

  /// No description provided for @reviewLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'후기를 불러올 수 없습니다'**
  String get reviewLoadFailed;

  /// No description provided for @reviewDeleted.
  ///
  /// In ko, this message translates to:
  /// **'후기가 삭제되었습니다'**
  String get reviewDeleted;

  /// No description provided for @reviewDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'후기 삭제에 실패했습니다'**
  String get reviewDeleteFailed;

  /// No description provided for @noPermission.
  ///
  /// In ko, this message translates to:
  /// **'권한이 없습니다'**
  String get noPermission;

  /// No description provided for @meetupInfoRefreshed.
  ///
  /// In ko, this message translates to:
  /// **'모임 정보가 업데이트되었습니다'**
  String get meetupInfoRefreshed;

  /// No description provided for @meetupCancelledSuccessfully.
  ///
  /// In ko, this message translates to:
  /// **'모임이 성공적으로 취소되었습니다'**
  String get meetupCancelledSuccessfully;

  /// No description provided for @deleteReviewTitle.
  ///
  /// In ko, this message translates to:
  /// **'후기 삭제'**
  String get deleteReviewTitle;

  /// No description provided for @deleteReviewConfirmMessage.
  ///
  /// In ko, this message translates to:
  /// **'정말로 후기를 삭제하시겠습니까?\n\n모든 참여자의 프로필에서 후기가 제거됩니다.'**
  String get deleteReviewConfirmMessage;

  /// No description provided for @noParticipantsYet.
  ///
  /// In ko, this message translates to:
  /// **'아직 참여자가 없습니다'**
  String get noParticipantsYet;

  /// No description provided for @participantsCountLabel.
  ///
  /// In ko, this message translates to:
  /// **'참여자 ({count}명)'**
  String participantsCountLabel(int count);

  /// No description provided for @viewAndRespondToReview.
  ///
  /// In ko, this message translates to:
  /// **'후기 확인 및 수락'**
  String get viewAndRespondToReview;

  /// No description provided for @reviewByAuthor.
  ///
  /// In ko, this message translates to:
  /// **'{name}님의 후기'**
  String reviewByAuthor(String name);

  /// No description provided for @replyingTo.
  ///
  /// In ko, this message translates to:
  /// **'{name}님에게 답글'**
  String replyingTo(String name);

  /// No description provided for @cancelReply.
  ///
  /// In ko, this message translates to:
  /// **'답글 취소'**
  String get cancelReply;

  /// No description provided for @writeReplyHint.
  ///
  /// In ko, this message translates to:
  /// **'답글을 입력하세요...'**
  String get writeReplyHint;

  /// No description provided for @noContent.
  ///
  /// In ko, this message translates to:
  /// **'내용 없음'**
  String get noContent;

  /// No description provided for @reviewAlreadyAccepted.
  ///
  /// In ko, this message translates to:
  /// **'이미 수락한 후기입니다'**
  String get reviewAlreadyAccepted;

  /// No description provided for @reviewAlreadyRejected.
  ///
  /// In ko, this message translates to:
  /// **'이미 거절한 후기입니다'**
  String get reviewAlreadyRejected;

  /// No description provided for @reviewAlreadyResponded.
  ///
  /// In ko, this message translates to:
  /// **'이미 응답한 요청입니다'**
  String get reviewAlreadyResponded;

  /// No description provided for @hideReview.
  ///
  /// In ko, this message translates to:
  /// **'후기 숨기기'**
  String get hideReview;

  /// No description provided for @unhideReview.
  ///
  /// In ko, this message translates to:
  /// **'후기 표시'**
  String get unhideReview;

  /// No description provided for @hideReviewConfirm.
  ///
  /// In ko, this message translates to:
  /// **'이 후기를 프로필에서 숨기시겠습니까?\n다른 사람들에게는 보이지 않게 됩니다.'**
  String get hideReviewConfirm;

  /// No description provided for @unhideReviewConfirm.
  ///
  /// In ko, this message translates to:
  /// **'이 후기를 다시 표시하시겠습니까?'**
  String get unhideReviewConfirm;

  /// No description provided for @reviewHidden.
  ///
  /// In ko, this message translates to:
  /// **'후기가 숨겨졌습니다'**
  String get reviewHidden;

  /// No description provided for @reviewUnhidden.
  ///
  /// In ko, this message translates to:
  /// **'후기가 표시됩니다'**
  String get reviewUnhidden;

  /// No description provided for @reviewHideFailed.
  ///
  /// In ko, this message translates to:
  /// **'후기 숨김 처리에 실패했습니다'**
  String get reviewHideFailed;

  /// No description provided for @reviewUnhideFailed.
  ///
  /// In ko, this message translates to:
  /// **'후기 표시 처리에 실패했습니다'**
  String get reviewUnhideFailed;

  /// No description provided for @deleteReviewSuccess.
  ///
  /// In ko, this message translates to:
  /// **'후기가 삭제되었습니다'**
  String get deleteReviewSuccess;

  /// No description provided for @deleteReviewFailed.
  ///
  /// In ko, this message translates to:
  /// **'후기 삭제에 실패했습니다'**
  String get deleteReviewFailed;

  /// No description provided for @reviewApprovalRequestMessage.
  ///
  /// In ko, this message translates to:
  /// **'{authorName}님이 \"{meetupTitle}\" 모임 후기 수락을 요청했습니다.'**
  String reviewApprovalRequestMessage(String authorName, String meetupTitle);

  /// No description provided for @updateMeetup.
  ///
  /// In ko, this message translates to:
  /// **'모임 수정하기'**
  String get updateMeetup;

  /// No description provided for @pleaseEnterTitle.
  ///
  /// In ko, this message translates to:
  /// **'제목을 입력해주세요'**
  String get pleaseEnterTitle;

  /// No description provided for @titleMinLength.
  ///
  /// In ko, this message translates to:
  /// **'제목은 2글자 이상 입력해주세요'**
  String get titleMinLength;

  /// No description provided for @pleaseEnterDescription.
  ///
  /// In ko, this message translates to:
  /// **'설명을 입력해주세요'**
  String get pleaseEnterDescription;

  /// No description provided for @pleaseEnterTime.
  ///
  /// In ko, this message translates to:
  /// **'시간을 입력해주세요'**
  String get pleaseEnterTime;

  /// No description provided for @timeHint.
  ///
  /// In ko, this message translates to:
  /// **'예: 14:00 또는 14:00~16:00'**
  String get timeHint;

  /// No description provided for @reviewDetails.
  ///
  /// In ko, this message translates to:
  /// **'후기 상세'**
  String get reviewDetails;

  /// No description provided for @likes.
  ///
  /// In ko, this message translates to:
  /// **'좋아요'**
  String get likes;

  /// No description provided for @likesCount.
  ///
  /// In ko, this message translates to:
  /// **'{count, plural, =0{좋아요 0개} =1{좋아요 1개} other{좋아요 {count}개}}'**
  String likesCount(int count);

  /// No description provided for @viewAllComments.
  ///
  /// In ko, this message translates to:
  /// **'댓글 {count}개 모두 보기'**
  String viewAllComments(int count);

  /// No description provided for @noCommentsYet.
  ///
  /// In ko, this message translates to:
  /// **'첫 댓글을 남겨보세요'**
  String get noCommentsYet;

  /// No description provided for @beFirstToComment.
  ///
  /// In ko, this message translates to:
  /// **'Be the first to comment!'**
  String get beFirstToComment;

  /// No description provided for @commentFeatureComingSoon.
  ///
  /// In ko, this message translates to:
  /// **'댓글 기능은 곧 제공될 예정입니다'**
  String get commentFeatureComingSoon;

  /// No description provided for @meetupParticipants.
  ///
  /// In ko, this message translates to:
  /// **'함께한 사람들 ({count}명)'**
  String meetupParticipants(int count);

  /// No description provided for @deletedAccount.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴한 계정'**
  String get deletedAccount;

  /// No description provided for @visibilityPublic.
  ///
  /// In ko, this message translates to:
  /// **'전체공개'**
  String get visibilityPublic;

  /// No description provided for @visibilityFriends.
  ///
  /// In ko, this message translates to:
  /// **'친구공개'**
  String get visibilityFriends;

  /// No description provided for @cannotOpenLink.
  ///
  /// In ko, this message translates to:
  /// **'링크를 열 수 없습니다'**
  String get cannotOpenLink;

  /// No description provided for @cancelMeetupMessage.
  ///
  /// In ko, this message translates to:
  /// **'정말로 \"{meetupTitle}\" 모임을 취소하시겠습니까?'**
  String cancelMeetupMessage(String meetupTitle);

  /// No description provided for @warningTitle.
  ///
  /// In ko, this message translates to:
  /// **'주의사항'**
  String get warningTitle;

  /// No description provided for @cancelMeetupWarning1.
  ///
  /// In ko, this message translates to:
  /// **'취소된 모임은 복구할 수 없습니다'**
  String get cancelMeetupWarning1;

  /// No description provided for @cancelMeetupWarning2.
  ///
  /// In ko, this message translates to:
  /// **'참여 중인 모든 사용자에게 알림이 발송됩니다'**
  String get cancelMeetupWarning2;

  /// No description provided for @yesCancel.
  ///
  /// In ko, this message translates to:
  /// **'예, 취소합니다'**
  String get yesCancel;

  /// No description provided for @dm.
  ///
  /// In ko, this message translates to:
  /// **'DM'**
  String get dm;

  /// No description provided for @directMessage.
  ///
  /// In ko, this message translates to:
  /// **'쪽지 보내기'**
  String get directMessage;

  /// No description provided for @newMessage.
  ///
  /// In ko, this message translates to:
  /// **'새 메시지'**
  String get newMessage;

  /// No description provided for @sendMessage.
  ///
  /// In ko, this message translates to:
  /// **'메시지 보내기'**
  String get sendMessage;

  /// No description provided for @typeMessage.
  ///
  /// In ko, this message translates to:
  /// **'메시지를 입력하세요'**
  String get typeMessage;

  /// No description provided for @noConversations.
  ///
  /// In ko, this message translates to:
  /// **'대화 내역이 없습니다'**
  String get noConversations;

  /// No description provided for @startFirstConversation.
  ///
  /// In ko, this message translates to:
  /// **'첫 대화를 시작해보세요!'**
  String get startFirstConversation;

  /// No description provided for @cannotSendDM.
  ///
  /// In ko, this message translates to:
  /// **'이 사용자에게 메시지를 보낼 수 없습니다'**
  String get cannotSendDM;

  /// No description provided for @blockedUser.
  ///
  /// In ko, this message translates to:
  /// **'차단된 사용자입니다'**
  String get blockedUser;

  /// No description provided for @anonymousUser.
  ///
  /// In ko, this message translates to:
  /// **'익명{number}'**
  String anonymousUser(String number);

  /// No description provided for @anonymousMessage.
  ///
  /// In ko, this message translates to:
  /// **'익명의 메시지'**
  String get anonymousMessage;

  /// No description provided for @dmFrom.
  ///
  /// In ko, this message translates to:
  /// **'{name}님의 메시지'**
  String dmFrom(String name);

  /// No description provided for @read.
  ///
  /// In ko, this message translates to:
  /// **'읽음'**
  String get read;

  /// No description provided for @unread.
  ///
  /// In ko, this message translates to:
  /// **'읽지 않음'**
  String get unread;

  /// No description provided for @maxMessageLength.
  ///
  /// In ko, this message translates to:
  /// **'메시지는 최대 500자까지 입력 가능합니다'**
  String get maxMessageLength;

  /// No description provided for @messageEmpty.
  ///
  /// In ko, this message translates to:
  /// **'메시지를 입력해주세요'**
  String get messageEmpty;

  /// No description provided for @messageSent.
  ///
  /// In ko, this message translates to:
  /// **'메시지를 전송했습니다'**
  String get messageSent;

  /// No description provided for @messageSendFailed.
  ///
  /// In ko, this message translates to:
  /// **'메시지 전송에 실패했습니다'**
  String get messageSendFailed;

  /// No description provided for @conversationWith.
  ///
  /// In ko, this message translates to:
  /// **'{name}님과의 대화'**
  String conversationWith(String name);

  /// No description provided for @loadingMessages.
  ///
  /// In ko, this message translates to:
  /// **'메시지를 불러오는 중...'**
  String get loadingMessages;

  /// No description provided for @noMessages.
  ///
  /// In ko, this message translates to:
  /// **'아직 메시지가 없습니다'**
  String get noMessages;

  /// No description provided for @blockThisUser.
  ///
  /// In ko, this message translates to:
  /// **'이 사용자 차단하기'**
  String get blockThisUser;

  /// No description provided for @blockConfirm.
  ///
  /// In ko, this message translates to:
  /// **'정말로 차단하시겠습니까?'**
  String get blockConfirm;

  /// No description provided for @dmNotAvailable.
  ///
  /// In ko, this message translates to:
  /// **'메시지 기능을 사용할 수 없습니다'**
  String get dmNotAvailable;

  /// No description provided for @friendsOnly.
  ///
  /// In ko, this message translates to:
  /// **'친구 공개'**
  String get friendsOnly;

  /// No description provided for @signUpFirstMessage.
  ///
  /// In ko, this message translates to:
  /// **'아래 \"회원가입하기\" 버튼을 눌러\n한양메일 인증을 먼저 진행해주세요.'**
  String get signUpFirstMessage;

  /// No description provided for @none.
  ///
  /// In ko, this message translates to:
  /// **'없음'**
  String get none;

  /// No description provided for @deleteReasonNoLongerUse.
  ///
  /// In ko, this message translates to:
  /// **'더 이상 사용하지 않아요'**
  String get deleteReasonNoLongerUse;

  /// No description provided for @deleteReasonMissingFeatures.
  ///
  /// In ko, this message translates to:
  /// **'원하는 기능이 없어요'**
  String get deleteReasonMissingFeatures;

  /// No description provided for @deleteReasonPrivacyConcerns.
  ///
  /// In ko, this message translates to:
  /// **'개인정보 보호가 걱정돼요'**
  String get deleteReasonPrivacyConcerns;

  /// No description provided for @deleteReasonSwitchingService.
  ///
  /// In ko, this message translates to:
  /// **'다른 서비스를 사용할 거예요'**
  String get deleteReasonSwitchingService;

  /// No description provided for @deleteReasonNewAccount.
  ///
  /// In ko, this message translates to:
  /// **'계정을 새로 만들고 싶어요'**
  String get deleteReasonNewAccount;

  /// No description provided for @deleteReasonOther.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get deleteReasonOther;

  /// No description provided for @selectDeleteReason.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴 사유 선택'**
  String get selectDeleteReason;

  /// No description provided for @otherReasonOptional.
  ///
  /// In ko, this message translates to:
  /// **'기타 사유 (선택)'**
  String get otherReasonOptional;

  /// No description provided for @deleteDataNotice.
  ///
  /// In ko, this message translates to:
  /// **'삭제될 데이터 안내'**
  String get deleteDataNotice;

  /// No description provided for @postDeleteTip.
  ///
  /// In ko, this message translates to:
  /// **'💡 게시글을 삭제하고 싶다면? 탈퇴하기 전에 \"내 게시글 관리\"에서 삭제하세요!'**
  String get postDeleteTip;

  /// No description provided for @finalWarning.
  ///
  /// In ko, this message translates to:
  /// **'최종 경고'**
  String get finalWarning;

  /// No description provided for @reallyDeleteAccount.
  ///
  /// In ko, this message translates to:
  /// **'정말로 계정을 삭제하시겠습니까?'**
  String get reallyDeleteAccount;

  /// No description provided for @actionCannotBeUndone.
  ///
  /// In ko, this message translates to:
  /// **'이 작업은 되돌릴 수 없습니다'**
  String get actionCannotBeUndone;

  /// No description provided for @accountRecoveryImpossible.
  ///
  /// In ko, this message translates to:
  /// **'❌ 계정 복구 불가능'**
  String get accountRecoveryImpossible;

  /// No description provided for @dataPermanentlyDeleted.
  ///
  /// In ko, this message translates to:
  /// **'❌ 데이터 영구 삭제'**
  String get dataPermanentlyDeleted;

  /// No description provided for @reRegistrationRequired.
  ///
  /// In ko, this message translates to:
  /// **'❌ 재가입 필요'**
  String get reRegistrationRequired;

  /// No description provided for @postsAnonymized.
  ///
  /// In ko, this message translates to:
  /// **'✅ 게시글 익명 처리'**
  String get postsAnonymized;

  /// No description provided for @deleteReasonLabel.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴 사유'**
  String get deleteReasonLabel;

  /// No description provided for @postsAnonymizedAutomatic.
  ///
  /// In ko, this message translates to:
  /// **'게시글: 익명 처리 (자동)'**
  String get postsAnonymizedAutomatic;

  /// No description provided for @deletionFailed.
  ///
  /// In ko, this message translates to:
  /// **'삭제 실패'**
  String get deletionFailed;

  /// No description provided for @accountDeletionIrreversible.
  ///
  /// In ko, this message translates to:
  /// **'⚠️ 계정 삭제 시 복구가 불가능합니다'**
  String get accountDeletionIrreversible;

  /// No description provided for @immediatelyDeleted.
  ///
  /// In ko, this message translates to:
  /// **'즉시 삭제'**
  String get immediatelyDeleted;

  /// No description provided for @anonymized.
  ///
  /// In ko, this message translates to:
  /// **'익명 처리'**
  String get anonymized;

  /// No description provided for @identityVerification.
  ///
  /// In ko, this message translates to:
  /// **'본인 확인'**
  String get identityVerification;

  /// No description provided for @reLoginForVerification.
  ///
  /// In ko, this message translates to:
  /// **'본인 확인을 위해 Google 계정으로 다시 로그인합니다.'**
  String get reLoginForVerification;

  /// No description provided for @deleteButtonGoogleLogin.
  ///
  /// In ko, this message translates to:
  /// **'\"계정 삭제\" 버튼을 누르면 Google 로그인 창이 표시됩니다.'**
  String get deleteButtonGoogleLogin;

  /// No description provided for @deleteButtonAppleLogin.
  ///
  /// In ko, this message translates to:
  /// **'\"계정 삭제\" 버튼을 누르면 Apple 로그인 창이 표시됩니다.'**
  String get deleteButtonAppleLogin;

  /// No description provided for @accountDeletedImmediatelyAfterAuth.
  ///
  /// In ko, this message translates to:
  /// **'⚠️ 재인증 후 계정이 즉시 삭제됩니다'**
  String get accountDeletedImmediatelyAfterAuth;

  /// No description provided for @reallyDelete.
  ///
  /// In ko, this message translates to:
  /// **'정말 삭제하시겠습니까?'**
  String get reallyDelete;

  /// No description provided for @deleteConfirmationMessage.
  ///
  /// In ko, this message translates to:
  /// **'이 작업은 되돌릴 수 없으며, 모든 데이터가 영구적으로 삭제됩니다. 게시글은 \"탈퇴한 사용자\"로 표시됩니다.'**
  String get deleteConfirmationMessage;

  /// No description provided for @accountDeleted.
  ///
  /// In ko, this message translates to:
  /// **'계정이 삭제되었습니다'**
  String get accountDeleted;

  /// No description provided for @personalInfo.
  ///
  /// In ko, this message translates to:
  /// **'개인정보 (이메일, 이름, 프로필 사진, 전화번호, 생년월일, 학교 정보, 자기소개)'**
  String get personalInfo;

  /// No description provided for @friendRelationships.
  ///
  /// In ko, this message translates to:
  /// **'친구 관계 (모든 친구 목록, 친구 요청)'**
  String get friendRelationships;

  /// No description provided for @meetups.
  ///
  /// In ko, this message translates to:
  /// **'모임 (주최한 모임 삭제, 참여 중인 모임에서 자동 탈퇴)'**
  String get meetups;

  /// No description provided for @uploadedFiles.
  ///
  /// In ko, this message translates to:
  /// **'업로드한 파일 (프로필 사진, 게시글 이미지, 모든 업로드 파일)'**
  String get uploadedFiles;

  /// No description provided for @postsAndComments.
  ///
  /// In ko, this message translates to:
  /// **'게시글 & 댓글 (탈퇴한 사용자로 표시, 대화 맥락 유지)'**
  String get postsAndComments;

  /// No description provided for @imageDisplayIssueDetected.
  ///
  /// In ko, this message translates to:
  /// **'이미지 표시 문제 감지'**
  String get imageDisplayIssueDetected;

  /// No description provided for @optional.
  ///
  /// In ko, this message translates to:
  /// **'(선택)'**
  String get optional;

  /// No description provided for @optionalField.
  ///
  /// In ko, this message translates to:
  /// **'(선택)'**
  String get optionalField;

  /// No description provided for @publicMeeting.
  ///
  /// In ko, this message translates to:
  /// **'전체 공개'**
  String get publicMeeting;

  /// No description provided for @participantCount.
  ///
  /// In ko, this message translates to:
  /// **'{current}/{total}명'**
  String participantCount(String current, String total);

  /// No description provided for @leaveChatRoom.
  ///
  /// In ko, this message translates to:
  /// **'채팅방 나가기'**
  String get leaveChatRoom;

  /// No description provided for @bioPlaceholder.
  ///
  /// In ko, this message translates to:
  /// **'한 줄 소개를 입력하세요 (선택)'**
  String get bioPlaceholder;

  /// No description provided for @userMessage.
  ///
  /// In ko, this message translates to:
  /// **'{user}님의 메시지'**
  String userMessage(Object user);

  /// No description provided for @imageSelectionError.
  ///
  /// In ko, this message translates to:
  /// **'이미지 선택 중 오류가 발생했습니다'**
  String get imageSelectionError;

  /// No description provided for @meetupUpdatedSuccess.
  ///
  /// In ko, this message translates to:
  /// **'모임이 성공적으로 수정되었습니다.'**
  String get meetupUpdatedSuccess;

  /// No description provided for @meetupUpdateError.
  ///
  /// In ko, this message translates to:
  /// **'모임 수정 중 오류가 발생했습니다'**
  String get meetupUpdateError;

  /// No description provided for @meetupImage.
  ///
  /// In ko, this message translates to:
  /// **'모임 이미지'**
  String get meetupImage;

  /// No description provided for @nicknameQuestion.
  ///
  /// In ko, this message translates to:
  /// **'닉네임이 무엇인가요?'**
  String get nicknameQuestion;

  /// No description provided for @notification.
  ///
  /// In ko, this message translates to:
  /// **'알림'**
  String get notification;

  /// No description provided for @messageFrom.
  ///
  /// In ko, this message translates to:
  /// **'{user}님의 메시지'**
  String messageFrom(Object user);

  /// No description provided for @reportComment.
  ///
  /// In ko, this message translates to:
  /// **'댓글 신고'**
  String get reportComment;

  /// No description provided for @reportConfirm.
  ///
  /// In ko, this message translates to:
  /// **'해당 댓글을 신고하시겠습니까?'**
  String get reportConfirm;

  /// No description provided for @reportError.
  ///
  /// In ko, this message translates to:
  /// **'댓글 작성자 정보가 올바르지 않습니다'**
  String get reportError;

  /// No description provided for @cafe.
  ///
  /// In ko, this message translates to:
  /// **'카페'**
  String get cafe;

  /// No description provided for @friendsOnlyBadge.
  ///
  /// In ko, this message translates to:
  /// **'친구 공개'**
  String get friendsOnlyBadge;

  /// No description provided for @ukraine.
  ///
  /// In ko, this message translates to:
  /// **'우크라이나'**
  String get ukraine;

  /// No description provided for @editMeetupButton.
  ///
  /// In ko, this message translates to:
  /// **'모임 수정하기'**
  String get editMeetupButton;

  /// No description provided for @anonymousDescription.
  ///
  /// In ko, this message translates to:
  /// **'게시판에 올라온 익명의 작성자와 소통해보세요.'**
  String get anonymousDescription;

  /// No description provided for @friendSelection.
  ///
  /// In ko, this message translates to:
  /// **'친구 선택'**
  String get friendSelection;

  /// No description provided for @noFriendsInCategory.
  ///
  /// In ko, this message translates to:
  /// **'친구가 없습니다'**
  String get noFriendsInCategory;

  /// No description provided for @addFriendsToCategory.
  ///
  /// In ko, this message translates to:
  /// **'이 카테고리에 친구를 추가해보세요'**
  String get addFriendsToCategory;

  /// No description provided for @registrationRequired.
  ///
  /// In ko, this message translates to:
  /// **'회원가입 필요'**
  String get registrationRequired;

  /// No description provided for @accountSelection.
  ///
  /// In ko, this message translates to:
  /// **'계정 선택'**
  String get accountSelection;

  /// No description provided for @continueWithWefillingAccount.
  ///
  /// In ko, this message translates to:
  /// **'Wefilling 계정으로 계속'**
  String get continueWithWefillingAccount;

  /// No description provided for @addAnotherAccount.
  ///
  /// In ko, this message translates to:
  /// **'다른 계정 추가'**
  String get addAnotherAccount;

  /// No description provided for @appInfo.
  ///
  /// In ko, this message translates to:
  /// **'앱 정보'**
  String get appInfo;

  /// No description provided for @appInfoTitle.
  ///
  /// In ko, this message translates to:
  /// **'Wefilling'**
  String get appInfoTitle;

  /// No description provided for @appVersion.
  ///
  /// In ko, this message translates to:
  /// **'버전'**
  String get appVersion;

  /// No description provided for @appTaglineShort.
  ///
  /// In ko, this message translates to:
  /// **'함께하면 즐거운 대학 생활'**
  String get appTaglineShort;

  /// No description provided for @copyright.
  ///
  /// In ko, this message translates to:
  /// **'© 2025 Wefilling. All rights reserved.'**
  String get copyright;

  /// No description provided for @patentPending.
  ///
  /// In ko, this message translates to:
  /// **'특허 출원 중'**
  String get patentPending;

  /// No description provided for @patentApplicationNumber.
  ///
  /// In ko, this message translates to:
  /// **'출원번호: 제10-2025-0187957호'**
  String get patentApplicationNumber;

  /// No description provided for @patentInventionTitle.
  ///
  /// In ko, this message translates to:
  /// **'발명의 명칭: AI 기반 소셜 네트워크 자동 분류 및 지능형 정보 관리 시스템'**
  String get patentInventionTitle;

  /// No description provided for @deletedUser.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴한 사용자'**
  String get deletedUser;

  /// No description provided for @blockUserTitle.
  ///
  /// In ko, this message translates to:
  /// **'사용자 차단'**
  String get blockUserTitle;

  /// No description provided for @blockUserMessage.
  ///
  /// In ko, this message translates to:
  /// **'{userName}님을 차단하시겠습니까?'**
  String blockUserMessage(String userName);

  /// No description provided for @blockUserWarningTitle.
  ///
  /// In ko, this message translates to:
  /// **'차단 시 다음과 같이 됩니다:'**
  String get blockUserWarningTitle;

  /// No description provided for @blockUserWarning1.
  ///
  /// In ko, this message translates to:
  /// **'해당 사용자의 게시물과 댓글이 보이지 않습니다'**
  String get blockUserWarning1;

  /// No description provided for @blockUserWarning2.
  ///
  /// In ko, this message translates to:
  /// **'해당 사용자가 만든 모임이 보이지 않습니다'**
  String get blockUserWarning2;

  /// No description provided for @blockUserWarning3.
  ///
  /// In ko, this message translates to:
  /// **'상호 간에 메시지를 주고받을 수 없습니다'**
  String get blockUserWarning3;

  /// No description provided for @blockUserWarning4.
  ///
  /// In ko, this message translates to:
  /// **'언제든지 차단을 해제할 수 있습니다'**
  String get blockUserWarning4;

  /// No description provided for @blockUserButton.
  ///
  /// In ko, this message translates to:
  /// **'차단하기'**
  String get blockUserButton;

  /// No description provided for @unblockUserTitle.
  ///
  /// In ko, this message translates to:
  /// **'차단 해제'**
  String get unblockUserTitle;

  /// No description provided for @unblockUserMessage.
  ///
  /// In ko, this message translates to:
  /// **'{userName}님의 차단을 해제하시겠습니까?\n\n차단 해제 후 해당 사용자의 콘텐츠를 다시 볼 수 있습니다.'**
  String unblockUserMessage(String userName);

  /// No description provided for @unblockUserButton.
  ///
  /// In ko, this message translates to:
  /// **'차단 해제'**
  String get unblockUserButton;

  /// No description provided for @reportTitle.
  ///
  /// In ko, this message translates to:
  /// **'신고하기'**
  String get reportTitle;

  /// No description provided for @reportPostTitle.
  ///
  /// In ko, this message translates to:
  /// **'게시물 신고하기'**
  String get reportPostTitle;

  /// No description provided for @reportCommentTitle.
  ///
  /// In ko, this message translates to:
  /// **'댓글 신고하기'**
  String get reportCommentTitle;

  /// No description provided for @reportMeetupTitle.
  ///
  /// In ko, this message translates to:
  /// **'모임 신고하기'**
  String get reportMeetupTitle;

  /// No description provided for @reportUserTitle.
  ///
  /// In ko, this message translates to:
  /// **'사용자 신고하기'**
  String get reportUserTitle;

  /// No description provided for @reportReasonSelect.
  ///
  /// In ko, this message translates to:
  /// **'신고 사유를 선택해주세요'**
  String get reportReasonSelect;

  /// No description provided for @reportDescriptionLabel.
  ///
  /// In ko, this message translates to:
  /// **'상세 설명 (선택사항)'**
  String get reportDescriptionLabel;

  /// No description provided for @reportDescriptionHint.
  ///
  /// In ko, this message translates to:
  /// **'신고 사유에 대한 자세한 설명을 입력해주세요'**
  String get reportDescriptionHint;

  /// No description provided for @reportWarning.
  ///
  /// In ko, this message translates to:
  /// **'신고는 검토 후 처리되며, 허위 신고 시 제재를 받을 수 있습니다.'**
  String get reportWarning;

  /// No description provided for @reportButton.
  ///
  /// In ko, this message translates to:
  /// **'신고하기'**
  String get reportButton;

  /// No description provided for @reportSuccess.
  ///
  /// In ko, this message translates to:
  /// **'신고가 접수되었습니다. 검토 후 처리하겠습니다.'**
  String get reportSuccess;

  /// No description provided for @reportFailed.
  ///
  /// In ko, this message translates to:
  /// **'신고 접수에 실패했습니다. 다시 시도해주세요.'**
  String get reportFailed;

  /// No description provided for @recommendedPlaces.
  ///
  /// In ko, this message translates to:
  /// **'추천 장소'**
  String get recommendedPlaces;

  /// No description provided for @customLocation.
  ///
  /// In ko, this message translates to:
  /// **'직접 입력'**
  String get customLocation;

  /// No description provided for @noRecommendedPlaces.
  ///
  /// In ko, this message translates to:
  /// **'추천 장소가 없습니다'**
  String get noRecommendedPlaces;

  /// No description provided for @pleaseSelectCategory.
  ///
  /// In ko, this message translates to:
  /// **'카테고리를 선택해주세요'**
  String get pleaseSelectCategory;

  /// No description provided for @titleMinLengthError.
  ///
  /// In ko, this message translates to:
  /// **'제목은 최소 2자 이상이어야 합니다'**
  String get titleMinLengthError;

  /// No description provided for @addImage.
  ///
  /// In ko, this message translates to:
  /// **'이미지 추가'**
  String get addImage;

  /// No description provided for @tapToSelectFromGallery.
  ///
  /// In ko, this message translates to:
  /// **'탭하여 갤러리에서 선택'**
  String get tapToSelectFromGallery;

  /// No description provided for @changeImageTooltip.
  ///
  /// In ko, this message translates to:
  /// **'이미지 변경'**
  String get changeImageTooltip;

  /// No description provided for @removeImageTooltip.
  ///
  /// In ko, this message translates to:
  /// **'이미지 제거'**
  String get removeImageTooltip;

  /// No description provided for @searchPostsHint.
  ///
  /// In ko, this message translates to:
  /// **'스토리 찾기'**
  String get searchPostsHint;

  /// No description provided for @searchMeetupsHint.
  ///
  /// In ko, this message translates to:
  /// **'모임 찾기'**
  String get searchMeetupsHint;

  /// No description provided for @emailLoginTitle.
  ///
  /// In ko, this message translates to:
  /// **'이메일로 로그인'**
  String get emailLoginTitle;

  /// No description provided for @emailLoginDescription.
  ///
  /// In ko, this message translates to:
  /// **'등록된 이메일과 비밀번호로 로그인해주세요.'**
  String get emailLoginDescription;

  /// No description provided for @emailSignUpTitle.
  ///
  /// In ko, this message translates to:
  /// **'이메일로 회원가입'**
  String get emailSignUpTitle;

  /// No description provided for @emailSignUpDescription.
  ///
  /// In ko, this message translates to:
  /// **'로그인에 사용할 이메일과 비밀번호를 설정해주세요.'**
  String get emailSignUpDescription;

  /// No description provided for @emailId.
  ///
  /// In ko, this message translates to:
  /// **'아이디(이메일)'**
  String get emailId;

  /// No description provided for @passwordHint.
  ///
  /// In ko, this message translates to:
  /// **'8자 이상'**
  String get passwordHint;

  /// No description provided for @passwordPlaceholder.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 입력'**
  String get passwordPlaceholder;

  /// No description provided for @passwordInputHint.
  ///
  /// In ko, this message translates to:
  /// **'8자 이상 입력'**
  String get passwordInputHint;

  /// No description provided for @confirmPasswordPlaceholder.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 한 번 더 입력'**
  String get confirmPasswordPlaceholder;

  /// No description provided for @confirmPasswordHint.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 다시 입력해주세요'**
  String get confirmPasswordHint;

  /// No description provided for @emailHelperText.
  ///
  /// In ko, this message translates to:
  /// **'자주 사용하는 이메일을 입력하세요'**
  String get emailHelperText;

  /// No description provided for @invalidEmailFormat.
  ///
  /// In ko, this message translates to:
  /// **'올바른 이메일 형식이 아닙니다'**
  String get invalidEmailFormat;

  /// No description provided for @emailAlreadyUsed.
  ///
  /// In ko, this message translates to:
  /// **'이미 사용 중인 이메일입니다'**
  String get emailAlreadyUsed;

  /// No description provided for @passwordLengthRequirement.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호는 8자 이상이어야 합니다'**
  String get passwordLengthRequirement;

  /// No description provided for @signUpComplete.
  ///
  /// In ko, this message translates to:
  /// **'회원가입 완료'**
  String get signUpComplete;

  /// No description provided for @loginFailedGeneric.
  ///
  /// In ko, this message translates to:
  /// **'로그인에 실패했습니다. 이메일과 비밀번호를 확인해주세요.'**
  String get loginFailedGeneric;

  /// No description provided for @loginErrorGeneric.
  ///
  /// In ko, this message translates to:
  /// **'로그인 중 오류가 발생했습니다'**
  String get loginErrorGeneric;

  /// No description provided for @errorUserNotFound.
  ///
  /// In ko, this message translates to:
  /// **'등록되지 않은 이메일입니다.'**
  String get errorUserNotFound;

  /// No description provided for @errorWrongPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호가 올바르지 않습니다.'**
  String get errorWrongPassword;

  /// No description provided for @errorInvalidEmail.
  ///
  /// In ko, this message translates to:
  /// **'유효하지 않은 이메일 형식입니다.'**
  String get errorInvalidEmail;

  /// No description provided for @errorUserDisabled.
  ///
  /// In ko, this message translates to:
  /// **'비활성화된 계정입니다. 관리자에게 문의하세요.'**
  String get errorUserDisabled;

  /// No description provided for @errorTooManyRequests.
  ///
  /// In ko, this message translates to:
  /// **'로그인 시도가 너무 많습니다. 잠시 후 다시 시도해주세요.'**
  String get errorTooManyRequests;

  /// No description provided for @errorInvalidCredential.
  ///
  /// In ko, this message translates to:
  /// **'이메일 또는 비밀번호가 올바르지 않습니다.'**
  String get errorInvalidCredential;

  /// No description provided for @errorOperationNotAllowed.
  ///
  /// In ko, this message translates to:
  /// **'이 로그인 방식은 현재 비활성화되어 있습니다. Firebase 콘솔에서 활성화해주세요.'**
  String get errorOperationNotAllowed;

  /// No description provided for @pleaseEnterPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 입력해주세요'**
  String get pleaseEnterPassword;

  /// No description provided for @passwordMustBe8Chars.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호는 8자 이상이어야 합니다'**
  String get passwordMustBe8Chars;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호가 일치하지 않습니다'**
  String get passwordsDoNotMatch;

  /// No description provided for @pleaseEnterEmail.
  ///
  /// In ko, this message translates to:
  /// **'이메일을 입력해주세요'**
  String get pleaseEnterEmail;

  /// No description provided for @validEmailFormat.
  ///
  /// In ko, this message translates to:
  /// **'유효한 이메일 형식이 아닙니다'**
  String get validEmailFormat;

  /// No description provided for @emailAlreadyInUse.
  ///
  /// In ko, this message translates to:
  /// **'이미 사용 중인 이메일입니다. 다른 이메일을 입력해주세요.'**
  String get emailAlreadyInUse;

  /// No description provided for @weakPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호가 너무 약합니다. 더 강력한 비밀번호를 사용해주세요.'**
  String get weakPassword;

  /// No description provided for @pleaseSelectTime.
  ///
  /// In ko, this message translates to:
  /// **'시간을 선택해주세요'**
  String get pleaseSelectTime;

  /// No description provided for @meetupCreateFailed.
  ///
  /// In ko, this message translates to:
  /// **'모임 생성에 실패했습니다. 다시 시도해주세요.'**
  String get meetupCreateFailed;

  /// No description provided for @postTypeSectionTitle.
  ///
  /// In ko, this message translates to:
  /// **'게시글 유형'**
  String get postTypeSectionTitle;

  /// No description provided for @postTypeTextLabel.
  ///
  /// In ko, this message translates to:
  /// **'일반'**
  String get postTypeTextLabel;

  /// No description provided for @postTypePollLabel.
  ///
  /// In ko, this message translates to:
  /// **'투표'**
  String get postTypePollLabel;

  /// No description provided for @postTypePollHelper.
  ///
  /// In ko, this message translates to:
  /// **'투표는 1인 1표로 참여할 수 있어요. 선택지는 최대 8개까지 가능합니다.'**
  String get postTypePollHelper;

  /// No description provided for @pollQuestionHint.
  ///
  /// In ko, this message translates to:
  /// **'투표 질문을 입력하세요'**
  String get pollQuestionHint;

  /// No description provided for @pollOptionsTitle.
  ///
  /// In ko, this message translates to:
  /// **'투표 선택지'**
  String get pollOptionsTitle;

  /// No description provided for @pollOptionHint.
  ///
  /// In ko, this message translates to:
  /// **'선택지 {index}'**
  String pollOptionHint(int index);

  /// No description provided for @pollAddOptionLabel.
  ///
  /// In ko, this message translates to:
  /// **'선택지 추가 ({current}/{max})'**
  String pollAddOptionLabel(int current, int max);

  /// No description provided for @pollVoteLabel.
  ///
  /// In ko, this message translates to:
  /// **'투표'**
  String get pollVoteLabel;

  /// No description provided for @pollParticipantsCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}명 참여'**
  String pollParticipantsCount(int count);

  /// No description provided for @pollVoteButton.
  ///
  /// In ko, this message translates to:
  /// **'투표하기'**
  String get pollVoteButton;

  /// No description provided for @pollVoteSuccess.
  ///
  /// In ko, this message translates to:
  /// **'투표가 완료되었습니다.'**
  String get pollVoteSuccess;

  /// No description provided for @pollVoteFailed.
  ///
  /// In ko, this message translates to:
  /// **'투표에 실패했습니다.'**
  String get pollVoteFailed;

  /// No description provided for @pollLoginToVote.
  ///
  /// In ko, this message translates to:
  /// **'로그인 후 투표할 수 있어요.'**
  String get pollLoginToVote;

  /// No description provided for @pollVoteToSeeResults.
  ///
  /// In ko, this message translates to:
  /// **'투표 후 결과를 확인할 수 있어요.'**
  String get pollVoteToSeeResults;

  /// No description provided for @moreOptions.
  ///
  /// In ko, this message translates to:
  /// **'더보기'**
  String get moreOptions;

  /// No description provided for @pollVotesUnit.
  ///
  /// In ko, this message translates to:
  /// **'{count}명'**
  String pollVotesUnit(int count);

  /// No description provided for @categorySelectAtLeastOne.
  ///
  /// In ko, this message translates to:
  /// **'카테고리를 최소 1개 이상 선택해주세요.'**
  String get categorySelectAtLeastOne;

  /// No description provided for @postImageUploading.
  ///
  /// In ko, this message translates to:
  /// **'이미지를 업로드 중입니다. 잠시만 기다려주세요...'**
  String get postImageUploading;

  /// No description provided for @totalImageSizeWarning.
  ///
  /// In ko, this message translates to:
  /// **'경고: 총 이미지 크기가 {sizeMB}MB입니다. 게시글 등록에 시간이 걸릴 수 있습니다.'**
  String totalImageSizeWarning(String sizeMB);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
