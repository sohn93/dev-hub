# Heosi 개발 허브

개인 게임 프로젝트의 기획과 기술 문서를 프로젝트·카테고리별로 모아 보는 정적 문서 허브입니다.

첫 번째 사례는 Unity 6000.3.8f1 기반의 Android 모바일 게임 공통 기반입니다. uGUI 런타임과 Firebase, Google Mobile Ads 연동을 세 개의 embedded UPM 패키지로 분리한 과정과 검증 결과를 공개합니다.

## 로컬에서 보기

```powershell
python -m http.server 8000
```

브라우저에서 `http://localhost:8000`을 엽니다.

## 문서 추가

1. 새 문서 파일을 만듭니다.

```powershell
.\scripts\new-document.ps1 -Slug my-document -Title "새 문서"
```

2. `templates/card.example.js`를 참고해 `data.js`의 알맞은 섹션에 카드를 등록합니다.
3. 검증을 실행합니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-site.ps1
```

## 파일 구조

| 경로 | 역할 |
| --- | --- |
| `index.html` | 프로젝트와 문서를 탐색하는 허브 홈 |
| `data.js` | 사이트 정보, 프로젝트, 섹션, 문서 카드 |
| `app.js` | 검색, 필터, 정렬, 내비게이션 |
| `hub.css` | 허브 홈 전용 디자인 |
| `style.css` | 상세 문서 디자인 시스템 |
| `docs/` | 공개 기술 문서 |
| `templates/` | 문서와 카드 작성 템플릿 |
| `scripts/` | 생성 및 검증 도구 |

## 배포

`main` 브랜치의 저장소 루트를 GitHub Pages 소스로 사용합니다. 모든 링크는 프로젝트 사이트 경로에서도 동작하도록 상대 경로로 작성합니다.

## 공개 원칙

- 확인된 사실과 측정 결과만 공개합니다.
- 미검증 항목은 성공으로 표현하지 않습니다.
- Firebase 설정, 서명 파일, 광고 운영 키, APK와 Unity SDK payload는 포함하지 않습니다.

