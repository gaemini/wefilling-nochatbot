// scripts/add_drinks_places.js
// 추천 장소 Drinks(drink) 문서에 장소를 "추가"하는 스크립트 (덮어쓰기 X)
//
// - 문서 ID가 'Drinks'로 되어 있는 경우가 있어 'drink'와 'Drinks' 둘 다 업데이트합니다.
// - 중복 방지: url 기준으로 이미 존재하면 추가하지 않습니다.
//
// 준비:
// - 프로젝트 루트에 serviceAccountKey.json 파일이 있어야 합니다.
// - scripts 폴더에서 npm install 후 실행하세요.

const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

const NEW_PLACES = [
  {
    name: '투다리 한양대점',
    url: 'https://map.naver.com/p/entry/place/37143072?c=17.49,0,0,0,dh',
  },
  {
    name: '만취',
    url: 'https://map.naver.com/p/entry/place/1859648742?c=17.49,0,0,0,dh&placePath=/home?from=map&fromPanelNum=1&additionalHeight=76&timestamp=202602072149&locale=ko&svcName=map_pcv5',
  },
];

async function upsertPlaces(docId) {
  const ref = db.collection('recommended_places').doc(docId);
  const snap = await ref.get();
  const data = snap.exists ? snap.data() : null;
  const existing = Array.isArray(data?.places) ? data.places : [];

  const byUrl = new Map();
  for (const p of existing) {
    if (p && typeof p.url === 'string') byUrl.set(p.url, p);
  }

  let maxOrder = 0;
  for (const p of existing) {
    const order = typeof p?.order === 'number' ? p.order : 0;
    if (order > maxOrder) maxOrder = order;
  }

  let added = 0;
  const updated = [...existing];

  for (const place of NEW_PLACES) {
    if (!place.url || byUrl.has(place.url)) continue;
    maxOrder += 1;
    updated.push({
      name: place.name,
      url: place.url,
      order: maxOrder,
    });
    byUrl.set(place.url, place);
    added += 1;
  }

  // order 기준으로 정렬
  updated.sort((a, b) => (a.order ?? 0) - (b.order ?? 0));

  await ref.set({ places: updated }, { merge: true });
  return { added, total: updated.length, existed: snap.exists };
}

async function main() {
  try {
    console.log('🍻 Drinks 추천 장소 추가 시작...\n');

    const targets = ['drink', 'Drinks'];
    for (const docId of targets) {
      const res = await upsertPlaces(docId);
      console.log(
        `✅ recommended_places/${docId} (${res.existed ? 'update' : 'create'}) - 추가: ${res.added}개, 총: ${res.total}개`,
      );
    }

    console.log('\n🎉 완료! (앱은 문서 ID "drink" 사용을 권장합니다)');
    process.exit(0);
  } catch (e) {
    console.error('❌ 실패:', e);
    process.exit(1);
  }
}

main();

