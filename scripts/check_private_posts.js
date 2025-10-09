// Firebase Console에서 실행할 스크립트
// Firestore Database → 쿼리 탭에서 실행

// 1. 모든 비공개 게시글 조회
// collection: posts
// where: visibility == "category"

// 2. 특정 게시글의 allowedUserIds 확인
// 정민지가 올린 게시글 ID를 여기에 입력
const postId = "FjhiF549UYsBCCnqcVTn"; // 문제의 게시글 ID

// Firebase Console에서 직접 이 게시글을 열어서 확인:
// 1. posts 컬렉션 → 해당 문서 클릭
// 2. allowedUserIds 필드 확인
// 3. 남평찬의 User ID가 이 배열에 있는지 확인

console.log("Firebase Console에서 확인할 사항:");
console.log("1. posts 컬렉션에서 문서 ID:", postId, "를 찾으세요");
console.log("2. 해당 문서의 필드를 확인하세요:");
console.log("   - visibility: 'category'인지 확인");
console.log("   - allowedUserIds: 배열에 어떤 User ID가 있는지 확인");
console.log("   - userId: 작성자 ID 확인");
console.log("3. 남평찬의 User ID가 allowedUserIds에 없어야 합니다!");

