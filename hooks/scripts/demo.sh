#!/bin/bash

# GitHub Integration Hooks 데모 스크립트
# Hook들의 실제 동작을 시연하는 스크립트

set -euo pipefail

# 색상 출력용
GREEN='\033[0;32m'
BLUE='\033[0;34m' 
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 설정 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}GitHub Integration Hooks 데모${NC}"
echo "=================================="

# 1. Plan to Issue Hook 데모
echo -e "\n${YELLOW}1. Plan to Issue Hook 데모${NC}"
echo "사용자가 계획 관련 프롬프트를 입력했을 때의 동작을 시연합니다."

read -p "Enter를 눌러 계속하세요..."

echo "시뮬레이션 프롬프트: '새로운 사용자 인증 시스템을 구현하는 계획을 세워줘'"

cat << 'EOF' | "$ROOT_DIR/hooks/scripts/plan-to-issue.sh"
{
    "prompt": "새로운 사용자 인증 시스템을 구현하는 계획을 세워줘\n\n1. OAuth 2.0 통합\n2. 비밀번호 정책 강화\n3. 2단계 인증 추가\n4. 세션 관리 개선\n5. 보안 로깅 구현"
}
EOF

echo -e "${GREEN}→ GitHub Issue가 생성되었습니다!${NC}"

# 2. Todo to Project Hook 데모  
echo -e "\n${YELLOW}2. Todo to Project Hook 데모${NC}"
echo "TodoWrite 도구 사용 시의 동작을 시연합니다."

read -p "Enter를 눌러 계속하세요..."

echo "시뮬레이션 Todo 데이터:"

cat << 'EOF' | "$ROOT_DIR/hooks/scripts/todo-to-project.sh"
{
    "tool_name": "TodoWrite",
    "tool_input": {
        "todos": [
            {
                "id": "demo-1",
                "content": "OAuth 2.0 클라이언트 설정",
                "status": "pending",
                "priority": "high"
            },
            {
                "id": "demo-2",
                "content": "비밀번호 유효성 검사 로직 구현",
                "status": "in_progress", 
                "priority": "high"
            },
            {
                "id": "demo-3",
                "content": "2FA 토큰 생성기 구현",
                "status": "completed",
                "priority": "medium"
            }
        ]
    }
}
EOF

echo -e "${GREEN}→ Todo 상태가 GitHub Project에 반영되었습니다!${NC}"

# 3. GitHub API 유틸리티 데모
echo -e "\n${YELLOW}3. GitHub API 유틸리티 데모${NC}"
echo "GitHub API 래퍼 스크립트의 기능을 시연합니다."

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    read -p "Enter를 눌러 계속하세요..."
    
    echo "최근 이슈 검색 중..."
    "$ROOT_DIR/hooks/utils/github-api.sh" search-issues "label:claude-plan" 3 | jq -r '.items[] | "- #\(.number): \(.title)"' 2>/dev/null || echo "검색된 이슈가 없습니다."
    
    echo -e "${GREEN}→ GitHub API가 정상적으로 동작합니다!${NC}"
else
    echo -e "${YELLOW}GITHUB_TOKEN이 설정되지 않아 실제 API 호출은 건너뜁니다.${NC}"
fi

# 4. 워크플로우 설명
echo -e "\n${YELLOW}4. 전체 워크플로우${NC}"
echo "Claude Code에서 실제 사용 시의 워크플로우:"

cat << 'EOF'

┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  사용자 프롬프트  │───▶│  Plan to Issue   │───▶│  GitHub Issue   │
│  (계획 관련)     │    │      Hook        │    │     생성        │
└─────────────────┘    └──────────────────┘    └─────────────────┘

┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   TodoWrite     │───▶│ Todo to Project  │───▶│ GitHub Project  │
│     도구        │    │      Hook        │    │   상태 업데이트  │
└─────────────────┘    └──────────────────┘    └─────────────────┘

실제 사용 예시:
1. "새 기능 구현 계획을 세워줘" → GitHub Issue 자동 생성
2. Claude가 Todo 리스트 생성 → Project에 자동 추가
3. Todo 상태 변경 → Project 컬럼 자동 이동
4. Todo 완료 → 관련 Issue 자동 업데이트

EOF

echo -e "${GREEN}데모가 완료되었습니다!${NC}"
echo ""
echo "실제 설정 방법은 SETUP.md 파일을 참조하세요."
echo "테스트 실행: ./hooks/scripts/test-hooks.sh"