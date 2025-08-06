#!/bin/bash

# GitHub API 유틸리티 스크립트
# 다양한 GitHub API 작업을 위한 공통 함수들

set -euo pipefail

# 설정 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# 환경 변수 로드
if [[ -f "$ROOT_DIR/.env" ]]; then
    source "$ROOT_DIR/.env"
fi

LOG_FILE="${LOG_FILE:-$ROOT_DIR/logs/github-hooks.log}"

# 로깅 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [GitHub-API] $1" | tee -a "$LOG_FILE"
}

# GitHub REST API 호출
github_rest_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local url="${GITHUB_API_BASE_URL:-https://api.github.com}${endpoint}"
    
    local curl_args=(
        -s -X "$method"
        -H "Authorization: token $GITHUB_TOKEN"
        -H "Content-Type: application/json"
        -H "Accept: application/vnd.github.v3+json"
        -H "User-Agent: Claude-Code-Hook/1.0"
    )
    
    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi
    
    curl "${curl_args[@]}" "$url"
}

# GitHub GraphQL API 호출
github_graphql_api() {
    local query="$1"
    local variables="${2:-{}}"
    
    local payload
    payload=$(jq -n \
        --arg query "$query" \
        --argjson variables "$variables" \
        '{query: $query, variables: $variables}')
    
    curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "User-Agent: Claude-Code-Hook/1.0" \
        -d "$payload" \
        "https://api.github.com/graphql"
}

# Issue 생성
create_issue() {
    local title="$1"
    local body="$2"
    local labels="${3:-[]}"
    local assignees="${4:-[]}"
    
    local issue_data
    issue_data=$(jq -n \
        --arg title "$title" \
        --arg body "$body" \
        --argjson labels "$labels" \
        --argjson assignees "$assignees" \
        '{title: $title, body: $body, labels: $labels, assignees: $assignees}')
    
    log "Creating issue: $title"
    github_rest_api "POST" "/repos/$GITHUB_OWNER/$GITHUB_REPO/issues" "$issue_data"
}

# Issue 업데이트
update_issue() {
    local issue_number="$1"
    local title="${2:-}"
    local body="${3:-}"
    local state="${4:-}"
    local labels="${5:-}"
    
    local update_data="{}"
    
    if [[ -n "$title" ]]; then
        update_data=$(echo "$update_data" | jq --arg title "$title" '. + {title: $title}')
    fi
    
    if [[ -n "$body" ]]; then
        update_data=$(echo "$update_data" | jq --arg body "$body" '. + {body: $body}')
    fi
    
    if [[ -n "$state" ]]; then
        update_data=$(echo "$update_data" | jq --arg state "$state" '. + {state: $state}')
    fi
    
    if [[ -n "$labels" ]]; then
        update_data=$(echo "$update_data" | jq --argjson labels "$labels" '. + {labels: $labels}')
    fi
    
    log "Updating issue #$issue_number"
    github_rest_api "PATCH" "/repos/$GITHUB_OWNER/$GITHUB_REPO/issues/$issue_number" "$update_data"
}

# Issue 검색
search_issues() {
    local query="$1"
    local limit="${2:-10}"
    
    local search_query="repo:$GITHUB_OWNER/$GITHUB_REPO $query"
    local encoded_query
    encoded_query=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$search_query'))")
    
    log "Searching issues: $query"
    github_rest_api "GET" "/search/issues?q=$encoded_query&per_page=$limit&sort=updated"
}

# Project 정보 조회 (GraphQL)
get_project_info() {
    local project_number="$1"
    
    local query='
    query($owner: String!, $number: Int!) {
        user(login: $owner) {
            projectV2(number: $number) {
                id
                title
                fields(first: 20) {
                    nodes {
                        ... on ProjectV2Field {
                            id
                            name
                        }
                        ... on ProjectV2SingleSelectField {
                            id
                            name
                            options {
                                id
                                name
                            }
                        }
                    }
                }
            }
        }
    }'
    
    local variables
    variables=$(jq -n \
        --arg owner "$GITHUB_OWNER" \
        --arg number "$project_number" \
        '{owner: $owner, number: ($number | tonumber)}')
    
    log "Getting project info for project #$project_number"
    github_graphql_api "$query" "$variables"
}

# Project에 이슈 추가 (GraphQL)
add_issue_to_project() {
    local project_id="$1"
    local issue_id="$2"
    
    local mutation='
    mutation($projectId: ID!, $contentId: ID!) {
        addProjectV2ItemByContentId(input: {
            projectId: $projectId
            contentId: $contentId
        }) {
            item {
                id
            }
        }
    }'
    
    local variables
    variables=$(jq -n \
        --arg projectId "$project_id" \
        --arg contentId "$issue_id" \
        '{projectId: $projectId, contentId: $contentId}')
    
    log "Adding issue to project"
    github_graphql_api "$mutation" "$variables"
}

# Project 아이템 상태 업데이트 (GraphQL)
update_project_item_status() {
    local project_id="$1"
    local item_id="$2"
    local field_id="$3"
    local option_id="$4"
    
    local mutation='
    mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $value: ProjectV2FieldValue!) {
        updateProjectV2ItemFieldValue(input: {
            projectId: $projectId
            itemId: $itemId
            fieldId: $fieldId
            value: $value
        }) {
            projectV2Item {
                id
            }
        }
    }'
    
    local variables
    variables=$(jq -n \
        --arg projectId "$project_id" \
        --arg itemId "$item_id" \
        --arg fieldId "$field_id" \
        --arg optionId "$option_id" \
        '{
            projectId: $projectId,
            itemId: $itemId,
            fieldId: $fieldId,
            value: {singleSelectOptionId: $optionId}
        }')
    
    log "Updating project item status"
    github_graphql_api "$mutation" "$variables"
}

# 도움말 표시
show_help() {
    cat << EOF
GitHub API 유틸리티 스크립트

사용법:
  $0 <command> [arguments...]

명령어:
  create-issue <title> <body> [labels] [assignees]
  update-issue <number> [title] [body] [state] [labels]
  search-issues <query> [limit]
  get-project-info <project_number>
  add-issue-to-project <project_id> <issue_id>
  update-project-item-status <project_id> <item_id> <field_id> <option_id>

예제:
  $0 create-issue "Test Issue" "Test body" '["bug"]' '["username"]'
  $0 search-issues "label:claude-plan" 5
  $0 get-project-info 1

환경 변수:
  GITHUB_TOKEN        - GitHub Personal Access Token
  GITHUB_OWNER        - Repository owner
  GITHUB_REPO         - Repository name
  GITHUB_PROJECT_NUMBER - Default project number
EOF
}

# 메인 로직
main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        "create-issue")
            create_issue "$@"
            ;;
        "update-issue")
            update_issue "$@"
            ;;
        "search-issues")
            search_issues "$@"
            ;;
        "get-project-info")
            get_project_info "$@"
            ;;
        "add-issue-to-project")
            add_issue_to_project "$@"
            ;;
        "update-project-item-status")
            update_project_item_status "$@"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo "Unknown command: $command" >&2
            show_help
            exit 1
            ;;
    esac
}

# 스크립트가 직접 실행된 경우에만 main 함수 호출
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi