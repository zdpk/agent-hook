# Agent Hook 설정 가이드

이 문서는 Claude CLI 기반 index.md 자동 관리 Hook 설정 방법을 안내합니다.

## 1. 사전 준비

### Claude CLI 설치 및 설정

1. **Claude CLI 설치**
   ```bash
   # 설치 방법은 Claude Code 공식 문서 참조
   # https://docs.anthropic.com/en/docs/claude-code/quickstart
   ```

2. **Claude Pro 구독 필요**
   - Claude CLI 사용을 위해 Claude Pro 구독($20/월) 필요
   - API 토큰 비용 없이 구독으로 무제한 사용 가능

3. **Claude CLI 로그인**
   ```bash
   claude auth login
   ```

### GitHub Personal Access Token 생성 (선택사항)

1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. "Generate new token (classic)" 클릭
3. 다음 권한 선택:
   - `repo` (전체 저장소 접근)
   - `project` (프로젝트 접근)
   - `write:discussion` (토론 작성, 프로젝트 v2용)

### 필요한 도구 설치

```bash
# jq (JSON 처리용)
brew install jq  # macOS
# sudo apt install jq  # Ubuntu

# curl (이미 설치되어 있을 가능성 높음)
# Python 3 (JSON 파싱용, 이미 설치되어 있을 가능성 높음)
```

## 2. 환경 설정

### 2.1 환경 설정

```bash
# Claude CLI가 정상 작동하는지 확인
claude --version

# 테스트 프롬프트 실행
claude -p "안녕하세요, 간단히 인사해주세요."
```

**추가 환경 변수 (GitHub 연동 시에만 필요)**:
```bash
# .env 파일 생성 (GitHub Hook 사용 시)
cp hooks/templates/.env.example .env

# .env 파일 편집
vim .env
```

`.env` 파일에 다음 내용 입력:
```bash
GITHUB_TOKEN=your_personal_access_token_here
GITHUB_OWNER=your_github_username  
GITHUB_REPO=your_repository_name
GITHUB_PROJECT_NUMBER=1
```

### 2.2 GitHub 설정 파일 생성

```bash
# GitHub 설정 파일 생성
cp hooks/configs/github.example.json hooks/configs/github.json

# 설정 파일 편집
vim hooks/configs/github.json
```

## 3. Claude Code 설정

### 3.1 Hook 설정 추가

Claude Code 설정 파일에 Hook 설정을 추가합니다:

```bash
# 현재 설정 파일 경로 확인
claude config --show-path

# 설정 파일 편집 (예: ~/.claude/settings.json)
vim ~/.claude/settings.json
```

`settings.json`에 다음 내용 추가:

```json
{
  "hooks": [
    {
      "event": "user-prompt-submit", 
      "commands": [
        "/absolute/path/to/hooks/scripts/plan-to-issue.sh"
      ],
      "description": "Plan을 GitHub Issue로 자동 생성"
    },
    {
      "event": "post-tool-use",
      "matcher": {
        "tool_name": "TodoWrite"
      },
      "commands": [
        "/absolute/path/to/hooks/scripts/todo-to-project.sh"
      ],
      "description": "Todo 상태 변경을 GitHub Project에 반영"
    }
  ]
}
```

**중요**: 스크립트 경로는 절대 경로로 지정해야 합니다.

### 3.2 템플릿 사용 (선택사항)

```bash
# 템플릿을 기본 설정으로 복사
cp hooks/templates/claude-settings.json ~/.claude/settings.json

# 경로 수정 필요!
vim ~/.claude/settings.json
```

## 4. 테스트

### 4.1 기본 연결 테스트

```bash
# GitHub API 연결 테스트
source .env
./hooks/utils/github-api.sh search-issues "is:open" 1
```

### 4.2 Hook 테스트

```bash
# Plan to Issue Hook 테스트
echo '{"prompt": "새로운 기능을 구현하는 계획을 세워보자"}' | ./hooks/scripts/plan-to-issue.sh

# Todo to Project Hook 테스트  
echo '{"tool_name": "TodoWrite", "tool_input": {"todos": [{"id": "1", "content": "테스트", "status": "pending", "priority": "high"}]}}' | ./hooks/scripts/todo-to-project.sh
```

## 5. 사용법

### 5.1 Plan → Issue 자동 생성

Claude에게 계획 관련 질문을 하면 자동으로 GitHub Issue가 생성됩니다:

```
"새로운 사용자 인증 시스템을 구현하는 계획을 세워줘"
"웹사이트 리팩토링 todo list를 만들어줘"
```

### 5.2 Todo → Project 상태 동기화

TodoWrite 도구를 사용하면 자동으로 GitHub Project에 반영됩니다:

- 새 Todo 생성 → Project에 카드 추가
- Todo 상태 변경 → Project 컬럼 이동
- Todo 완료 → 관련 Issue 업데이트

## 6. 문제 해결

### 로그 확인

```bash
# Hook 실행 로그 확인
tail -f hooks/logs/github-hooks.log
```

### 권한 확인

```bash
# 스크립트 실행 권한 확인
ls -la hooks/scripts/

# 권한 설정
chmod +x hooks/scripts/*.sh
chmod +x hooks/utils/*.sh
```

### 환경 변수 확인

```bash
# 환경 변수 로드 테스트
source .env
echo $GITHUB_TOKEN
echo $GITHUB_OWNER
echo $GITHUB_REPO
```

## 7. 고급 설정

### 7.1 Project v2 설정

GitHub Project v2를 사용하는 경우:

1. Project 설정 → Fields에서 Status 필드 확인
2. Status 옵션명 확인 (Todo, In Progress, Done 등)
3. `github.json`에서 `status_mapping` 수정

### 7.2 커스텀 라벨 및 템플릿

- `hooks/configs/github.json`에서 `default_labels` 수정
- `hooks/templates/plan_issue.md`에서 이슈 템플릿 커스터마이징

## 8. 보안 주의사항

- `.env` 파일을 절대 git에 커밋하지 마세요
- Personal Access Token은 필요한 최소 권한만 부여하세요
- 정기적으로 토큰을 재생성하세요