#!/bin/bash

# Todo to Project Hook for Claude Code
# TodoWrite 도구 사용 후 Todo 상태 변경을 GitHub Project에 반영

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

# JSON 파싱 함수
parse_json() {
    python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    result = data
    for key in '$1'.split('.'):
        if key and key in result:
            result = result[key]
        elif key and isinstance(result, list) and key.isdigit():
            result = result[int(key)]
        else:
            result = None
            break
    print(json.dumps(result, ensure_ascii=False) if result is not None else '\"\"')
except Exception as e:
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

# GitHub Project v2 API 호출 함수 (GraphQL)
github_graphql() {
    local query="$1"
    
    curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{\"query\": $(echo "$query" | jq -Rs .)}" \
        "https://api.github.com/graphql"
}

# Todo 상태를 Project 상태로 매핑
map_todo_status() {
    local status="$1"
    case "$status" in
        "pending") echo "Todo" ;;
        "in_progress") echo "In Progress" ;;
        "completed") echo "Done" ;;
        *) echo "Todo" ;;
    esac
}

# Project에서 관련 이슈 찾기
find_related_issue() {
    local todo_content="$1"
    
    # 최근 이슈들에서 유사한 내용 검색
    local issues_response
    issues_response=$(github_api "GET" "/repos/$GITHUB_OWNER/$GITHUB_REPO/issues?state=open&labels=claude-plan&per_page=10")
    
    # 간단한 키워드 매칭으로 관련 이슈 찾기
    echo "$issues_response" | python3 -c "
import json, sys
try:
    issues = json.load(sys.stdin)
    todo_content = '''$todo_content'''.lower()
    
    for issue in issues:
        if any(word in issue['title'].lower() or word in issue['body'].lower() 
               for word in todo_content.split()[:3] if len(word) > 2):
            print(issue['number'])
            break
except:
    pass
"
}

# 메인 로직
main() {
    log "Todo to Project Hook 실행 시작"
    
    # stdin으로부터 hook 데이터 읽기
    local hook_data
    hook_data=$(cat)
    
    log "Hook data 수신: $hook_data"
    
    # tool_name 확인
    local tool_name
    tool_name=$(echo "$hook_data" | parse_json "tool_name")
    
    if [[ "$tool_name" != "\"TodoWrite\"" ]]; then
        log "TodoWrite 도구가 아님. Hook 종료."
        exit 0
    fi
    
    # tool_input에서 todos 배열 추출
    local todos_data
    todos_data=$(echo "$hook_data" | parse_json "tool_input.todos")
    
    if [[ -z "$todos_data" || "$todos_data" == '""' ]]; then
        log "Todo 데이터가 없음. Hook 종료."
        exit 0
    fi
    
    log "Todo 데이터 처리 시작"
    
    # 각 todo 항목 처리
    echo "$todos_data" | python3 -c "
import json, sys, subprocess, os

try:
    todos = json.load(sys.stdin)
    
    for todo in todos:
        todo_id = todo.get('id', '')
        content = todo.get('content', '')
        status = todo.get('status', 'pending')
        priority = todo.get('priority', 'medium')
        
        print(f'Processing todo {todo_id}: {status}', file=sys.stderr)
        
        # 상태가 completed인 경우 관련 이슈 업데이트
        if status == 'completed':
            # 간단한 구현: 로그만 남기고 실제 Project 연동은 추후 구현
            print(f'Todo completed: {content}', file=sys.stderr)
        
        # 상태가 in_progress인 경우
        elif status == 'in_progress':
            print(f'Todo in progress: {content}', file=sys.stderr)
            
        # 새로운 pending todo인 경우
        elif status == 'pending':
            print(f'New todo: {content}', file=sys.stderr)
            
except Exception as e:
    print(f'Error processing todos: {e}', file=sys.stderr)
" 2>&1 | while read -r line; do
        log "$line"
    done
    
    # 성공 응답
    echo '{"success": true, "processed": true}'
    log "Todo to Project Hook 실행 완료"
}

# 실행
main "$@"