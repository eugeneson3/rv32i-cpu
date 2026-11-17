# RV32I Multi-cycle CPU

RV32I 명령어 실행 경로를 설계하고 누적합 프로그램의 레지스터·메모리 변화를 확인하였습니다. 팀 단위로 UVM 검증과 APB 주변장치 확장을 수행하였습니다.

- 수행 시기 2026.09
- 참여 형태 4인 팀
- 담당 범위 CPU Datapath·Control Unit RTL 설계 및 C 누적합 프로그램 동작 확인

[포트폴리오 상세 페이지](https://eugeneson3.github.io/projects/rv32i-cpu/)

## 프로젝트 목표

RISC-V 기본 정수 명령어를 실행하는 Multi-cycle CPU를 설계하고, 소프트웨어 실행과 버스 연결을 통해 RTL 동작을 확인하는 것을 목표로 하였습니다.

## 설계 및 구현

- Datapath에 PC, 레지스터 파일, ALU, 즉시값 생성 및 중간 결과 레지스터를 구성하였습니다.
- Control Unit FSM에서 명령어 종류에 따른 실행·메모리 접근·Write-back 순서를 제어하였습니다.
- C 누적합 프로그램의 어셈블리 흐름을 분석하고, 반복문과 함수 호출이 RTL 파형에 반영되는 과정을 확인하였습니다.
- 팀 통합 단계에서 APB의 IDLE·SETUP·ACCESS 상태와 ready 응답을 사용하여 메모리 및 GPIO 접근을 구성하였습니다.

## Troubleshooting

### 시프트 연산의 이동량 해석

팀 UVM 검증에서 SLL·SRL·SRA 연산의 기대값과 실제값이 불일치하였습니다.

발표 자료는 rs2 데이터 전체를 이동량으로 사용한 RTL을 원인으로 기록하고 있습니다.

팀 수정본에서 이동량을 rs2[4:0]로 제한하였습니다. SLL의 rs1=5, rs2=0xffffffff 사례에서 기대값 0x80000000을 확인하였습니다.

발표 기록에서 FAIL 4,072건이 0건으로 감소하였습니다. 공개된 CPU 스냅샷에는 수정 전 연산식이 보존되어 있습니다.

### 미실행 커버리지 조합

팀 UVM 발표 결과의 Functional Coverage는 99.56%입니다.

ADD의 첫 번째 피연산자 최댓값 조건과 AND·XOR의 두 번째 피연산자 최댓값 조건이 남아 있습니다.

발표 자료에 준비 레지스터를 유지한 Directed 시나리오 3개 및 주기적 레지스터 재초기화 방안을 정리하였습니다.

보강 방안은 후속 검증 항목으로 기록하였습니다.

## 검증 및 결과

- 본인 담당 결과는 CPU RTL 및 누적합 프로그램 동작 확인입니다.
- 김민석은 UVM 검증, 강건은 APB 연결, 정성하는 소프트웨어 흐름 설명을 담당하였습니다.
- 팀 UVM 검증 범위는 R형 10개와 I형 ALU 9개입니다. 준비 명령 144개, Directed 26개, Random 90,000개를 포함하여 총 90,170개를 검사하였습니다.
- 팀 발표 자료에 APB를 통한 Load/Store와 Basys3 ILA 관측 결과가 수록되어 있습니다.

## 소스코드 구조

cpu/는 TEAMPJ4_rv32i의 RTL 및 클럭·리셋 테스트벤치 스냅샷입니다. apb/는 GPIO 프로젝트에서 확인한 버전입니다. 발표의 CPU UVM 테스트벤치와 최종 시프트 수정본은 현재 공개 소스에서 확인되지 않아, 발표 수치는 팀 수행 기록으로 표기하였습니다.

| 경로 | 내용 |
| --- | --- |
| [cpu/rtl/datapath.sv](cpu/rtl/datapath.sv) | ALU, 레지스터 파일 및 Datapath |
| [cpu/rtl/control_unit.sv](cpu/rtl/control_unit.sv) | 명령어별 상태 제어 |
| [cpu/rtl/instruction_rom.sv](cpu/rtl/instruction_rom.sv) | 누적합 프로그램 및 테스트 명령 |
| [cpu/tb/tb_rv32i.sv](cpu/tb/tb_rv32i.sv) | 클럭·리셋 기반 시뮬레이션 진입점 |
| [apb/rtl/](apb/rtl/) | APB 및 GPIO 연결 버전 |
| [apb/rom_code_2.mem](apb/rom_code_2.mem) | APB 버전의 명령어 메모리 |

## 실행 방법

1. CPU 시뮬레이션은 cpu/를 작업 디렉터리로 사용하고 files.f를 컴파일 목록으로 지정합니다.
2. 최상위 테스트벤치는 tb_rv32i_cpu입니다. 기존 테스트벤치는 파형 관측 방식입니다.
3. APB 버전은 apb/를 작업 디렉터리로 사용하고 files.f와 rom_code_2.mem을 함께 사용합니다.

## 참고 자료

- [팀 최종 발표 자료 r9](https://docs.google.com/presentation/d/1rQOqn0zb5K-6F9mSDNCq0MLXzXdX3Gpm/edit)

## 소스 이력

2026년 11월 18일 로컬 프로젝트에서 구성한 공개 스냅샷입니다. 원본 파일의 상대 경로와 SHA-256은 [SOURCE_MANIFEST.json](SOURCE_MANIFEST.json)에 기록하였습니다. 빌드 산출물과 로컬 개발 환경은 제외하였습니다. 파일별 저작권 및 라이선스 고지를 유지하였습니다.

정적 검사에서는 기본 timescale을 1ns/1ps로 지정하였습니다. CPU에는 래치 추론 등의 진단이 남아 있습니다. 검사 결과는 docs/에 수록하였습니다.
