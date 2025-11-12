#!/bin/bash
OUTPUT="korean_audit.txt"
echo "🔍 하드코딩 한글 전수 조사" > $OUTPUT
echo "생성 시간: $(date)" >> $OUTPUT
echo "" >> $OUTPUT

# 1. const Text("한글") - 가장 확실한 하드코딩
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> $OUTPUT
echo "1️⃣ const Text 하드코딩 (높은 우선순위)" >> $OUTPUT
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> $OUTPUT
grep -rn 'const Text("[^"]*[가-힣]' lib/screens/ lib/widgets/ 2>/dev/null | grep -v "AppLocalizations" >> $OUTPUT

# 2. Text('한글') - 작은따옴표
echo "" >> $OUTPUT
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> $OUTPUT
echo "2️⃣ Text() 하드코딩" >> $OUTPUT
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> $OUTPUT
grep -rn "Text('[^']*[가-힣]" lib/screens/ lib/widgets/ 2>/dev/null | grep -v "AppLocalizations" | head -50 >> $OUTPUT

# 3. SnackBar 메시지
echo "" >> $OUTPUT
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> $OUTPUT
echo "3️⃣ SnackBar 메시지" >> $OUTPUT
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> $OUTPUT
grep -rn 'SnackBar.*content.*[가-힣]' lib/screens/ 2>/dev/null | head -30 >> $OUTPUT

# 4. AlertDialog 제목/내용
echo "" >> $OUTPUT
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> $OUTPUT
echo "4️⃣ AlertDialog 메시지" >> $OUTPUT
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> $OUTPUT
grep -rn 'title.*Text.*[가-힣]\|content.*Text.*[가-힣]' lib/screens/ 2>/dev/null | head -30 >> $OUTPUT

# 5. tooltip, hintText, labelText
echo "" >> $OUTPUT
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> $OUTPUT
echo "5️⃣ Tooltip/Hint/Label" >> $OUTPUT
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> $OUTPUT
grep -rn 'tooltip.*[가-힣]\|hintText.*[가-힣]\|labelText.*[가-힣]' lib/ 2>/dev/null | head -20 >> $OUTPUT

# 6. 통계
echo "" >> $OUTPUT
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> $OUTPUT
echo "📊 통계" >> $OUTPUT
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> $OUTPUT
CONST_COUNT=$(grep -r 'const Text(".*[가-힣]' lib/ 2>/dev/null | grep -v AppLocalizations | wc -l | tr -d ' ')
SNACK_COUNT=$(grep -r 'SnackBar.*[가-힣]' lib/screens/ 2>/dev/null | wc -l | tr -d ' ')
DIALOG_COUNT=$(grep -r 'AlertDialog' lib/screens/ 2>/dev/null | wc -l | tr -d ' ')

echo "const Text 하드코딩: ${CONST_COUNT}개" >> $OUTPUT
echo "SnackBar: ${SNACK_COUNT}개" >> $OUTPUT
echo "AlertDialog: ${DIALOG_COUNT}개" >> $OUTPUT

cat $OUTPUT


