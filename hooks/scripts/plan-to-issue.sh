#!/bin/bash

# Plan to Issue Hook for Claude Code
# 사용자 프롬프트에서 계획 관련 내용을 감지하고 GitHub Issue로 생성

set -euo pipefail

# 설정 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# 환경 변수 로드
if [[ -f "$ROOT_DIR/.env" ]]; then
    source "$ROOT_DIR/.env"
fi

# 설정 파일 로드
CONFIG_FILE="${HOOK_CONFIG_PATH:-$ROOT_DIR/configs/github.json}"
LOG_FILE="${LOG_FILE:-$ROOT_DIR/logs/github-hooks.log}"

# 로깅 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# JSON 파싱 함수 (jq 대체용 간단 파서)
parse_json() {
    python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(json.dumps(data.get('$1', ''), ensure_ascii=False))
except:
    print('\"\"')
" 2>/dev/null || echo '""'
}

# GitHub API 호출 함수
github_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local url="${GITHUB_API_BASE_URL:-https://api.github.com}${endpoint}"
    
    if [[ -n "$data" ]]; then
        curl -s -X "$method" \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/json" \
            -H "Accept: application/vnd.github.v3+json" \
            -d "$data" \
            "$url"
    else
        curl -s -X "$method" \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "$url"
    fi
}

# 메인 로직
main() {
    log "Plan to Issue Hook 실행 시작"
    
    # stdin으로부터 hook 데이터 읽기
    local hook_data
    hook_data=$(cat)
    
    log "Hook data 수신: $hook_data"
    
    # prompt 내용 추출
    local prompt
    prompt=$(echo "$hook_data" | parse_json "prompt")
    
    if [[ -z "$prompt" || "$prompt" == '""' ]]; then
        log "프롬프트 내용이 없음. Hook 종료."
        exit 0
    fi
    
    # 계획 관련 키워드 확인
    local keywords="plan|계획|todo|task|구현|implementation"
    if ! echo "$prompt" | grep -iE "$keywords" >/dev/null; then
        log "계획 관련 키워드가 없음. Hook 종료."
        exit 0
    fi
    
    log "계획 관련 프롬프트 감지됨"
    
    # 제목 생성 (첫 번째 줄 또는 요약)
    local title
    title=$(echo "$prompt" | head -1 | sed 's/^[#* ]*//g' | cut -c1-50)
    if [[ -z "$title" ]]; then
        title="Claude Plan - $(date '+%Y-%m-%d %H:%M')"
    fi
    
    # 이슈 본문 생성
    local issue_body
    issue_body=$(cat << EOF
# Claude Plan

## 요청 내용
$prompt

## 생성 정보
- **생성 시간**: $(date '+%Y-%m-%d %H:%M:%S')
- **생성자**: Claude Code Hook
- **트리거**: user-prompt-submit

---
*이 이슈는 Claude Code의 Plan → Issue Hook에 의해 자동으로 생성되었습니다.*
EOF
)
    
    # GitHub Issue 생성
    local issue_data
    issue_data=$(cat << EOF
{
    "title": "$title",
    "body": $(echo "$issue_body" | jq -Rs .),
    "labels": ["claude-plan", "automated"]
}
EOF
)
    
    log "GitHub Issue 생성 중..."
    local response
    response=$(github_api "POST" "/repos/$GITHUB_OWNER/$GITHUB_REPO/issues" "$issue_data")
    
    local issue_number
    issue_number=$(echo "$response" | parse_json "number")
    
    if [[ -n "$issue_number" && "$issue_number" != '""' ]]; then
        log "GitHub Issue #$issue_number 생성 완료"
        
        # Project에 추가 (옵션)
        if [[ "${GITHUB_PROJECT_NUMBER:-}" ]]; then
            log "Project에 Issue 추가 시도..."
            # Project v2 API는 복잡하므로 별도 스크립트로 분리 예정
        fi
        
        # 성공 응답
        echo '{"success": true, "issue_number": '$issue_number'}'
    else
        log "GitHub Issue 생성 실패: $response"
        echo '{"success": false, "error": "Issue creation failed"}'
        exit 1
    fi
}

# 실행
main "$@"