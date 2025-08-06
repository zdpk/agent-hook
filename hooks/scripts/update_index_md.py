import os
import sys
import subprocess
import shutil
import json
from datetime import datetime

# --- 설정 ---
BACKUP_DIR = ".index_backups"
MAX_RETRIES = 3
PROTECTED_DIRS = [".git", "node_modules", "__pycache__", ".index_backups"]
CLAUDE_CLI_TIMEOUT = 30  # Claude CLI 호출 타임아웃 (초)
# --- 설정 끝 ---

def check_claude_cli():
    """Claude CLI가 설치되어 있는지 확인합니다."""
    try:
        result = subprocess.run(['claude', '--version'], capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            print(f"Claude CLI 감지: {result.stdout.strip()}")
            return True
    except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.CalledProcessError):
        pass
    
    print("오류: Claude CLI를 찾을 수 없습니다.", file=sys.stderr)
    print("Claude CLI 설치: https://docs.anthropic.com/en/docs/claude-code", file=sys.stderr)
    return False

if not check_claude_cli():
    sys.exit(1)

def create_backup(file_path):
    """index.md 파일의 백업을 생성합니다."""
    if not os.path.exists(file_path):
        return None
    
    # 백업 디렉토리 생성
    backup_dir = os.path.join(os.path.dirname(file_path), BACKUP_DIR)
    os.makedirs(backup_dir, exist_ok=True)
    
    # 타임스탬프로 백업 파일명 생성
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_filename = f"index_md_backup_{timestamp}.md"
    backup_path = os.path.join(backup_dir, backup_filename)
    
    try:
        shutil.copy2(file_path, backup_path)
        print(f"백업 생성: {backup_path}")
        return backup_path
    except Exception as e:
        print(f"백업 생성 실패: {e}", file=sys.stderr)
        return None

def validate_index_md(file_path):
    """index.md 파일의 구조를 검증합니다."""
    if not os.path.exists(file_path):
        return True  # 새 파일은 유효한 것으로 간주
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # 기본 구조 검증
        required_sections = ["#", "## 주요 파일"]
        for section in required_sections:
            if section not in content:
                print(f"경고: '{file_path}'에 필수 섹션 '{section}'이 없습니다.", file=sys.stderr)
                return False
        
        return True
    except Exception as e:
        print(f"index.md 검증 실패: {e}", file=sys.stderr)
        return False

def restore_backup(original_path, backup_path):
    """백업에서 원본 파일을 복원합니다."""
    if backup_path and os.path.exists(backup_path):
        try:
            shutil.copy2(backup_path, original_path)
            print(f"백업에서 복원: {original_path}")
            return True
        except Exception as e:
            print(f"백업 복원 실패: {e}", file=sys.stderr)
    return False

def get_changed_files_with_status():
    """가장 최근 커밋에서 변경된 파일 목록과 상태를 가져옵니다."""
    try:
        # --name-status 옵션을 사용하여 파일 상태(A, M, D, R)를 함께 가져옵니다.
        result = subprocess.run(
            ['git', 'diff', 'HEAD~1', 'HEAD', '--name-status'],
            capture_output=True, text=True, check=True
        )
        lines = result.stdout.strip().split('\n')
        changes = []
        for line in lines:
            if not line:
                continue
            parts = line.split('\t')
            status = parts[0]
            # Renamed 파일은 R<점수> 형식으로 나오며, 이전/이후 경로가 탭으로 구분됩니다.
            if status.startswith('R'):
                old_path, new_path = parts[1], parts[2]
                changes.append(('D', old_path))  # 이전 경로는 삭제로 처리
                changes.append(('A', new_path))  # 새 경로는 추가로 처리
            else:
                changes.append((status, parts[1]))
        return changes
    except subprocess.CalledProcessError as e:
        print(f"Git diff 실행 중 오류 발생: {e}", file=sys.stderr)
        return []

def summarize_file_with_claude(file_path):
    """Claude CLI를 사용하여 파일 내용을 한 줄로 요약합니다. (재시도 로직 포함)"""
    if not os.path.exists(file_path) or os.path.getsize(file_path) == 0:
        return "파일이 비어 있거나 존재하지 않습니다."
    
    for attempt in range(MAX_RETRIES):
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # 파일 내용이 너무 길면 앞부분만 사용 (Claude CLI 입력 제한 고려)
            if len(content) > 8000:  # 대략 8KB 제한
                content = content[:8000] + "\n... (파일이 길어서 앞부분만 표시)"
            
            prompt = f"""다음 파일 내용의 핵심 역할을 한국어로 한 문장으로 요약해줘.
파일의 전체적인 목적과 기능에 초점을 맞춰서 설명해줘.
결과는 다른 부연 설명 없이, 오직 요약된 한 문장만 출력해줘.

파일 경로: {file_path}
--- 파일 내용 ---
{content}"""
            
            # Claude CLI 호출
            result = subprocess.run([
                'claude', '-p', prompt
            ], capture_output=True, text=True, timeout=CLAUDE_CLI_TIMEOUT)
            
            if result.returncode == 0 and result.stdout.strip():
                summary = result.stdout.strip()
                # 여러 줄인 경우 첫 번째 줄만 사용
                if '\n' in summary:
                    summary = summary.split('\n')[0]
                return summary
            else:
                raise subprocess.CalledProcessError(result.returncode, 'claude')
                
        except subprocess.TimeoutExpired:
            print(f"'{file_path}' 파일 요약 중 타임아웃 (시도 {attempt + 1}/{MAX_RETRIES})", file=sys.stderr)
        except subprocess.CalledProcessError as e:
            print(f"'{file_path}' 파일 요약 중 Claude CLI 오류 (시도 {attempt + 1}/{MAX_RETRIES}): {e}", file=sys.stderr)
        except Exception as e:
            print(f"'{file_path}' 파일 요약 중 오류 발생 (시도 {attempt + 1}/{MAX_RETRIES}): {e}", file=sys.stderr)
        
        if attempt == MAX_RETRIES - 1:
            return "요약 생성 중 오류 발생"

def update_index_md(directory, file_name, summary):
    """백업 및 검증과 함께 index.md 파일을 안전하게 업데이트합니다."""
    index_path = os.path.join(directory, 'index.md')
    backup_path = None
    
    try:
        # 기존 파일이 있으면 백업 생성
        if os.path.exists(index_path):
            backup_path = create_backup(index_path)
        
        entry = f"- `{file_name}`: {summary}"
        file_list_header = "## 주요 파일"
        
        if not os.path.exists(index_path):
            print(f"'{index_path}' 생성 중...")
            folder_name = os.path.basename(directory) if directory else "Root"
            content = f"# {folder_name}\n\n이 폴더의 역할을 설명해주세요.\n\n{file_list_header}\n{entry}\n"
            with open(index_path, 'w', encoding='utf-8') as f:
                f.write(content)
        else:
            print(f"'{index_path}' 업데이트 중...")
            with open(index_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            updated = False
            for i, line in enumerate(lines):
                if line.strip().startswith(f'- `{file_name}`'):
                    lines[i] = entry + '\n'
                    updated = True
                    break
            
            if not updated:
                try:
                    header_index = [i for i, line in enumerate(lines) if line.strip() == file_list_header][0]
                    lines.insert(header_index + 1, entry + '\n')
                except IndexError:
                    lines.append(f"\n{file_list_header}\n")
                    lines.append(entry + '\n')
            
            with open(index_path, 'w', encoding='utf-8') as f:
                f.writelines(lines)
        
        # 업데이트 후 검증
        if not validate_index_md(index_path):
            print(f"검증 실패: {index_path}", file=sys.stderr)
            if backup_path:
                restore_backup(index_path, backup_path)
            return False
        
        return True
        
    except Exception as e:
        print(f"index.md 업데이트 중 오류 발생: {e}", file=sys.stderr)
        if backup_path:
            restore_backup(index_path, backup_path)
        return False


def remove_entry_from_index_md(directory, file_name):
    """백업과 함께 index.md에서 파일 항목을 안전하게 삭제합니다."""
    index_path = os.path.join(directory, 'index.md')
    if not os.path.exists(index_path):
        return True

    backup_path = create_backup(index_path)
    
    try:
        print(f"'{index_path}'에서 '{file_name}' 항목 삭제 중...")
        with open(index_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        # 삭제할 라인을 제외한 나머지 라인만 필터링
        lines_to_keep = [line for line in lines if not line.strip().startswith(f'- `{file_name}`')]

        if len(lines) != len(lines_to_keep):
            with open(index_path, 'w', encoding='utf-8') as f:
                f.writelines(lines_to_keep)
            
            # 삭제 후 검증
            if not validate_index_md(index_path):
                print(f"삭제 후 검증 실패: {index_path}", file=sys.stderr)
                if backup_path:
                    restore_backup(index_path, backup_path)
                return False
            
            print(f"항목 삭제 완료.")
            return True
        else:
            print(f"삭제할 항목을 찾지 못했습니다.")
            return True
            
    except Exception as e:
        print(f"항목 삭제 중 오류 발생: {e}", file=sys.stderr)
        if backup_path:
            restore_backup(index_path, backup_path)
        return False


def is_protected_directory(directory):
    """보호된 디렉토리인지 확인합니다."""
    return any(protected in directory for protected in PROTECTED_DIRS)

def check_index_md_modifications():
    """index.md 파일이 직접 수정되었는지 확인합니다."""
    try:
        result = subprocess.run(
            ['git', 'diff', 'HEAD~1', 'HEAD', '--name-only'],
            capture_output=True, text=True, check=True
        )
        modified_files = result.stdout.strip().split('\n')
        index_modifications = [f for f in modified_files if f.endswith('index.md')]
        
        if index_modifications:
            print("경고: index.md 파일이 직접 수정되었습니다:", file=sys.stderr)
            for file in index_modifications:
                print(f"- {file}", file=sys.stderr)
            return True
        return False
    except subprocess.CalledProcessError:
        return False

def main():
    print("--- index.md 업데이트 Hook 시작 (v4: Claude CLI 통합) ---")
    
    # index.md 직접 수정 검사
    if check_index_md_modifications():
        print("index.md가 직접 수정되었지만 계속 진행합니다.", file=sys.stderr)
    
    changes = get_changed_files_with_status()

    if not changes:
        print("변경사항이 없어 Hook을 종료합니다.")
        sys.exit(0)

    updated_indices = set()
    failed_operations = []

    for status, file_path in changes:
        # 스크립트 자신이나 index.md 파일, 보호된 디렉토리의 변경은 무시
        if (file_path.endswith('update_index_md.py') or 
            file_path.endswith('index.md') or 
            is_protected_directory(file_path)):
            continue
        
        directory = os.path.dirname(file_path)
        file_name = os.path.basename(file_path)
        
        print(f"\n> 상태: {status}, 파일: {file_path}")

        success = False
        if status == 'A' or status == 'M':
            # 파일 추가 또는 수정 시 요약 후 업데이트
            summary = summarize_file_with_claude(file_path)
            success = update_index_md(directory, file_name, summary)
            
        elif status == 'D':
            # 파일 삭제 시 항목 제거
            success = remove_entry_from_index_md(directory, file_name)
        
        if success:
            updated_indices.add(os.path.join(directory, 'index.md'))
        else:
            failed_operations.append((status, file_path))

    print("\n--- index.md 업데이트 완료 ---")
    
    if failed_operations:
        print("실패한 작업:", file=sys.stderr)
        for status, file_path in failed_operations:
            print(f"- {status}: {file_path}", file=sys.stderr)
        print("Hook이 실패했습니다. 커밋이 중단됩니다.", file=sys.stderr)
        sys.exit(1)
    
    if updated_indices:
        print("성공적으로 업데이트된 index.md 파일:")
        for path in sorted([p for p in updated_indices if p]):
            print(f"- {path}")
    
    sys.exit(0)


if __name__ == "__main__":
    main()
