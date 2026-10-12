'use strict';
// 번역 언어 가드(순수 함수) 회귀 테스트. 네트워크·Gemini 호출 없음.
//   npm --prefix functions run build && node functions/scripts/test_translation_language_guard.js
const assert = require('node:assert/strict');
const {
  looksLikeTargetLanguage,
  translationMatchesTargetLanguage,
} = require('../lib/translation_language_guard');

let passed = 0;
function check(name, actual, expected) {
  assert.equal(actual, expected, name);
  passed++;
}

// ── 이미 대상 언어인지(번역 불필요 판정) ──────────────────────────────
const same = [
  ['스페인어 문장은 포르투갈어가 아니다', 'Me gusta que vengas para ayudar', 'pt', false],
  ['스페인어 문장은 스페인어다', 'Me gusta que vengas para ayudar a todos', 'es', true],
  ['이탈리아어 문장은 프랑스어가 아니다', 'Che bello la casa per la festa', 'fr', false],
  ['이탈리아어 문장은 이탈리아어다', 'Che bello la casa per la festa di oggi', 'it', true],
  ['영어 문장은 영어다', 'This is the best day and I love it', 'en', true],
  ['영어 문장은 스페인어가 아니다', 'This is the best day and I love it', 'es', false],
  ['포르투갈어 문장', 'Eu não sei o que fazer com isso', 'pt', true],
  ['포르투갈어 문장은 스페인어가 아니다', 'Eu não sei o que fazer com isso', 'es', false],
  ['프랑스어 문장', 'Je suis très content de vous voir', 'fr', true],
  ['독일어 문장', 'Ich habe das nicht gewusst und bin sehr müde', 'de', true],
  ['한 단어는 판정하지 않는다', 'Hello', 'en', false],
  ['한글은 ko', '안녕하세요 반갑습니다', 'ko', true],
  ['영어는 ko가 아니다', 'Nice to meet you', 'ko', false],
  ['가나가 있으면 ja', '今日はいい天気ですね', 'ja', true],
  ['한자만 있으면 ja가 아니다', '今天天气很好', 'ja', false],
  ['한자만 있으면 zh', '今天天气很好', 'zh', true],
  ['인도네시아어는 말레이어 가족으로 본다', 'Saya tidak tahu dengan yang ini', 'ms', true],
  ['키릴 문자는 ru', 'Привет, как дела у тебя сегодня', 'ru', true],
  ['베트남어', 'Xin chào, tôi là sinh viên và rất vui được gặp bạn', 'vi', true],
  ['베트남어 문장은 영어가 아니다', 'Xin chào, tôi là sinh viên và rất vui được gặp bạn', 'en', false],
];
for (const [name, text, target, expected] of same) {
  check(`looksLike ${target}: ${name}`, looksLikeTargetLanguage(text, target), expected);
}

// ── 번역문이 대상 언어인지 ───────────────────────────────────────────
const KO = '저는 오늘 친구와 함께 영화를 보러 갈 거예요';
const outputs = [
  ['영어 대상에 영어 번역', KO, 'I am going to watch a movie with my friend today', 'en', true],
  ['중국어 대상에 영어 출력', KO, 'I am going to watch a movie with my friend today', 'zh', false],
  ['영어 대상에 한국어 그대로 출력', KO, '저는 오늘 친구와 함께 영화를 보러 갈 거에요', 'en', false],
  ['스페인어 대상에 영어 출력', KO,
    'I am going to see a movie with my friend today and it will be fun', 'es', false],
  ['스페인어 대상에 스페인어 번역', KO,
    'Hoy voy al cine con mi amigo y será muy divertido', 'es', true],
  ['포르투갈어 대상에 스페인어 출력', KO,
    'Hoy voy a ir al cine con mi amigo porque es muy bueno para mí', 'pt', false],
  ['포르투갈어 대상에 포르투갈어 번역', KO,
    'Hoje eu vou ao cinema com o meu amigo e vai ser muito divertido', 'pt', true],
  ['이름뿐인 문장은 그대로 둔다', 'Starbucks Gangnam', 'Starbucks Gangnam', 'ko', true],
  ['일본어 대상에 한국어 출력', KO, '저는 오늘 친구와 함께 영화를 보러 갈 거에요', 'ja', false],
  ['중국어 대상에 일본어 그대로 출력', '今日は友達と映画を見に行きます', '今日は友達と映画を見に行きます。', 'zh', false],
  ['중국어 대상에 가나가 섞인 번역', KO, '今日は友達と映画を見に行きます', 'zh', false],
  ['한국어 대상에 브랜드가 섞인 번역', 'I really like the Wefilling app',
    'Wefilling 앱을 정말 좋아해요', 'ko', true],
  ['러시아어 대상에 러시아어', KO, 'Сегодня я иду в кино с другом, будет весело', 'ru', true],
  ['러시아어 대상에 영어', KO, 'Today I am going to the cinema with a friend and it will be fun', 'ru', false],
  ['URL·멘션은 판단에서 제외', 'Check https://example.com @minsu this is great today',
    '확인해 보세요 https://example.com @minsu 오늘 정말 멋져요', 'ko', true],
  ['짧은 결과는 판단하지 않는다', '네', 'Yes', 'en', true],
  ['베트남어 대상에 베트남어', KO, 'Hôm nay tôi sẽ đi xem phim với bạn và sẽ rất vui', 'vi', true],
  ['아랍어 대상에 영어', KO, 'Today I am going to watch a movie with my friend', 'ar', false],
];
for (const [name, source, output, target, expected] of outputs) {
  check(`output ${target}: ${name}`,
    translationMatchesTargetLanguage(source, output, target), expected);
}

console.log(`translation language guard: ${passed} checks passed`);
