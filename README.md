# Agent Hook

Claude Code용 고급 Hook 시스템으로, Git 커밋 시 파일 변경사항을 자동으로 추적하고 문서를 업데이트합니다.

## 주요 기능

### 🎯 update_index_md.py
각 디렉토리의 `index.md` 파일을 자동으로 관리하는 Git hook입니다.

**주요 특징:**
- ✅ **여러 디렉토리 동시 추적**: 한 번의 커밋에서 여러 디렉토리 변경사항 처리
- ✅ **자동 디렉토리 관리**: 새 디렉토리 생성 시 `index.md` 자동 생성
- ✅ **파일 동기화**: 파일 추가/삭제/수정 시 자동으로 문서 업데이트
- ✅ **완벽한 안전장치**: 백업/검증/롤백 시스템으로 안전한 작업 보장

**작동 방식:**
```
Git 커밋 → 변경 파일 감지 → Claude API로 요약 → index.md 업데이트 → 검증 → 백업 생성
```

### 🔒 안전성 보장
- **자동 백업**: 모든 수정 전 타임스탬프 백업 생성
- **구조 검증**: 필수 섹션 확인 및 무결성 검사
- **오류 복구**: 실패 시 자동 백업 복원
- **커밋 차단**: 작업 실패 시 커밋 중단으로 안전성 보장

## 설치 및 사용

### 1. 환경 설정
```bash
export ANTHROPIC_API_KEY="your_api_key_here"
```

### 2. Git Hook 설정
```bash
# 실행 권한 부여
chmod +x hooks/scripts/update_index_md.py

# Git hook으로 설정 (예시)
ln -s ../../hooks/scripts/update_index_md.py .git/hooks/post-commit
```

### 3. 테스트 실행
```bash
python test_hook.py
```

## 파일 구조

```
hooks/
├── scripts/
│   ├── update_index_md.py    # 메인 Hook 스크립트
│   ├── demo.sh              # 데모 실행 스크립트
│   ├── test-hooks.sh        # Hook 테스트 스크립트
│   ├── plan-to-issue.sh     # GitHub Issue 생성 Hook
│   └── todo-to-project.sh   # GitHub Project 연동 Hook
├── configs/
│   └── github.example.json  # GitHub 연동 설정 예시
├── templates/
│   ├── .env.example         # 환경 변수 템플릿
│   ├── claude-settings.json # Claude 설정 템플릿
│   └── plan_issue.md       # Issue 템플릿
└── utils/
    └── github-api.sh        # GitHub API 유틸리티

test_hook.py                 # Hook 검증 스크립트
```

## 개선사항 상세

### ✅ 1. 여러 디렉토리 변경 추적
- 모든 변경된 파일을 순회하며 각 디렉토리별로 처리
- `updated_indices` 집합으로 영향받은 모든 index.md 추적

### ✅ 2. 새 디렉토리 자동 index.md 생성
- 파일이 없으면 기본 템플릿으로 자동 생성
- 디렉토리명을 제목으로 사용하여 일관성 유지

### ✅ 3. 파일 추가/제거 동기화
- **추가/수정**: Claude API로 파일 요약 후 index.md 업데이트
- **삭제**: index.md에서 해당 파일 항목 제거
- **이름변경**: 삭제+추가로 분리하여 올바르게 처리

### ✅ 4. 검증 및 커밋 중단 (새로 추가)
- **백업 시스템**: 수정 전 `.index_backups/` 디렉토리에 자동 백업
- **구조 검증**: 필수 섹션(제목, "## 주요 파일") 확인
- **에러 처리**: API 최대 3회 재시도, 실패 시 롤백
- **커밋 중단**: 작업 실패 시 `sys.exit(1)`로 커밋 차단
- **보호 기능**: 시스템 디렉토리(.git, node_modules 등) 자동 제외

## 라이선스

MIT License
