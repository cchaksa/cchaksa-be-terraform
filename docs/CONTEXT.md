# CONTEXT.md

이 문서는 context 문서 작성 규칙을 정의한다.

## 1. 파일명 규칙
- 작업 context 파일명은 반드시 아래 형식을 사용한다.
  - `{작업명}-context.md`
- `{작업명}`은 소문자 kebab-case 권장
- 예시:
  - `scraper-async-migration-context.md`
  - `backend-serverless-cutover-context.md`

## 2. 필수 섹션
각 `docs/{작업명}-context.md`에는 아래 섹션을 반드시 포함한다.
- 배경
- 범위
- As-Is
- To-Be
- 구현 계획
- 실행 로그
- 검증 결과
- 전환 계획
- 롤백 계획
- 오픈 이슈

## 3. 상태 규칙
- 문서 상단에 상태를 명시한다.
- 허용 상태:
  - `planned`
  - `in-progress`
  - `validated`
  - `cutover`
  - `rolled-back`
  - `done`

## 4. 기록 규칙
- append-only 원칙으로 누적 기록한다.
- 정정이 필요한 경우 기존 내용을 지우지 말고 `정정` 섹션으로 남긴다.
- 수치/로그/근거에는 날짜(시간)와 환경을 함께 기록한다.

## 5. PR 연계 규칙
- PR에는 해당 context 파일 경로를 반드시 포함한다.
- plan/apply/test 결과 등 검증 증적을 링크 또는 요약으로 첨부한다.

