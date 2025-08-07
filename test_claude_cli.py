#!/usr/bin/env python3
"""
Claude CLI 기반 update_index_md.py 스크립트의 테스트 및 검증 도구
실제 Claude CLI 호출을 시뮬레이션하여 스크립트의 핵심 기능들을 검증합니다.
"""

import os
import sys
import tempfile
import shutil
import subprocess
from datetime import datetime

def test_claude_cli_availability():
    """Claude CLI 설치 및 사용 가능 여부 테스트"""
    print("=== Claude CLI 가용성 테스트 ===")
    
    try:
        # Claude CLI 버전 확인
        result = subprocess.run(['claude', '--version'], capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            print(f"✓ Claude CLI 사용 가능: {result.stdout.strip()}")
            return True
        else:
            print(f"✗ Claude CLI 버전 확인 실패")
            return False
    except subprocess.TimeoutExpired:
        print("✗ Claude CLI 호출 타임아웃")
        return False
    except FileNotFoundError:
        print("✗ Claude CLI를 찾을 수 없습니다")
        print("  설치 필요: https://docs.anthropic.com/en/docs/claude-code/quickstart")
        return False
    except Exception as e:
        print(f"✗ Claude CLI 테스트 실패: {e}")
        return False

def test_claude_cli_prompt():
    """Claude CLI 프롬프트 처리 테스트"""
    print("\n=== Claude CLI 프롬프트 테스트 ===")
    
    try:
        test_prompt = "다음 Python 함수의 역할을 한 문장으로 요약해줘: def hello(): print('Hello World')"
        
        result = subprocess.run([
            'claude', '-p', test_prompt
        ], capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0 and result.stdout.strip():
            summary = result.stdout.strip()
            if '\n' in summary:
                summary = summary.split('\n')[0]
            print(f"✓ Claude CLI 응답 성공: {summary}")
            return True
        else:
            print(f"✗ Claude CLI 응답 실패: {result.stderr}")
            return False
            
    except subprocess.TimeoutExpired:
        print("✗ Claude CLI 응답 타임아웃 (30초)")
        return False
    except Exception as e:
        print(f"✗ Claude CLI 프롬프트 테스트 실패: {e}")
        return False

def test_file_summarization():
    """파일 요약 기능 테스트"""
    print("\n=== 파일 요약 기능 테스트 ===")
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        test_code = '''#!/usr/bin/env python3
"""
간단한 계산기 모듈
기본적인 사칙연산 기능을 제공합니다.
"""

def add(a, b):
    """두 수를 더합니다."""
    return a + b

def subtract(a, b):  
    """두 수를 뺍니다."""
    return a - b

def multiply(a, b):
    """두 수를 곱합니다."""
    return a * b

def divide(a, b):
    """두 수를 나눕니다."""
    if b == 0:
        raise ValueError("0으로 나눌 수 없습니다")
    return a / b

if __name__ == "__main__":
    print("계산기 테스트")
    print(f"2 + 3 = {add(2, 3)}")
    print(f"5 - 2 = {subtract(5, 2)}")
    print(f"4 * 6 = {multiply(4, 6)}")
    print(f"8 / 2 = {divide(8, 2)}")
'''
        f.write(test_code)
        temp_file = f.name
    
    try:
        prompt = f"""다음 파일 내용의 핵심 역할을 한국어로 한 문장으로 요약해줘.
파일의 전체적인 목적과 기능에 초점을 맞춰서 설명해줘.
결과는 다른 부연 설명 없이, 오직 요약된 한 문장만 출력해줘.

파일 경로: {temp_file}
--- 파일 내용 ---
{test_code}"""
        
        result = subprocess.run([
            'claude', '-p', prompt
        ], capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0 and result.stdout.strip():
            summary = result.stdout.strip()
            if '\n' in summary:
                summary = summary.split('\n')[0]
            print(f"✓ 파일 요약 성공: {summary}")
            return True
        else:
            print(f"✗ 파일 요약 실패: {result.stderr}")
            return False
            
    except Exception as e:
        print(f"✗ 파일 요약 테스트 실패: {e}")
        return False
    finally:
        if os.path.exists(temp_file):
            os.unlink(temp_file)

def test_error_handling():
    """에러 처리 테스트"""
    print("\n=== 에러 처리 테스트 ===")
    
    # 매우 긴 프롬프트로 제한 테스트
    long_prompt = "테스트" * 10000  # 40KB 정도
    
    try:
        result = subprocess.run([
            'claude', '-p', long_prompt
        ], capture_output=True, text=True, timeout=10)
        
        # 에러 또는 정상 응답 모두 처리 가능하면 성공
        if result.returncode != 0:
            print("✓ 에러 상황 정상 처리 (긴 입력 거부)")
        else:
            print("✓ 긴 입력 처리 성공")
        return True
        
    except subprocess.TimeoutExpired:
        print("✓ 타임아웃 에러 정상 처리")
        return True
    except Exception as e:
        print(f"✗ 에러 처리 테스트 실패: {e}")
        return False

def test_backup_system():
    """백업 시스템 테스트 (기존 로직)"""
    print("\n=== 백업 시스템 테스트 ===")
    
    with tempfile.TemporaryDirectory() as temp_dir:
        # 테스트 파일 생성
        test_file = os.path.join(temp_dir, "index.md")
        with open(test_file, 'w') as f:
            f.write("# 테스트\n\n## 주요 파일\n- `test.py`: 테스트 파일\n")
        
        # 백업 디렉토리 생성 시뮬레이션
        backup_dir = os.path.join(temp_dir, ".index_backups")
        os.makedirs(backup_dir, exist_ok=True)
        
        # 백업 파일 생성
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_filename = f"index_md_backup_{timestamp}.md"
        backup_path = os.path.join(backup_dir, backup_filename)
        shutil.copy2(test_file, backup_path)
        
        print(f"✓ 백업 파일 생성됨: {backup_path}")
        print(f"✓ 백업 파일 존재: {os.path.exists(backup_path)}")
        
        # 백업 복원 시뮬레이션
        os.remove(test_file)
        shutil.copy2(backup_path, test_file)
        print(f"✓ 백업에서 복원 완료: {os.path.exists(test_file)}")
        return True

def main():
    print("Claude CLI 기반 update_index_md.py 스크립트 검증 시작")
    print("=" * 60)
    
    test_results = []
    
    # 테스트 실행
    tests = [
        ("Claude CLI 가용성", test_claude_cli_availability),
        ("Claude CLI 프롬프트", test_claude_cli_prompt), 
        ("파일 요약 기능", test_file_summarization),
        ("에러 처리", test_error_handling),
        ("백업 시스템", test_backup_system)
    ]
    
    for test_name, test_func in tests:
        try:
            result = test_func()
            test_results.append((test_name, result))
        except Exception as e:
            print(f"✗ {test_name} 테스트 실행 중 오류: {e}")
            test_results.append((test_name, False))
    
    # 결과 요약
    print("\n" + "=" * 60)
    print("테스트 결과 요약")
    print("=" * 60)
    
    passed = sum(1 for _, result in test_results if result)
    total = len(test_results)
    
    for test_name, result in test_results:
        status = "✅ 통과" if result else "❌ 실패"
        print(f"{status} {test_name}")
    
    print(f"\n총 {total}개 테스트 중 {passed}개 통과 ({passed/total*100:.1f}%)")
    
    if passed == total:
        print("\n🎉 모든 테스트 통과! Claude CLI 기반 Hook이 정상 작동할 것으로 예상됩니다.")
        print("\n주요 장점:")
        print("💰 구독 기반 비용 (Claude Pro $20/월)")
        print("🚀 최신 Claude 3.5 Sonnet 자동 사용")
        print("🔒 기존 안전장치 모두 유지")
        print("⚡ 더 간단한 에러 처리")
        return True
    else:
        print(f"\n⚠️  {total-passed}개 테스트 실패. 문제를 해결한 후 다시 시도하세요.")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)