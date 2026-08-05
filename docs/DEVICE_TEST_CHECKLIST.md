# Device test checklist

- [ ] 위치 권한 허용, 거부, 설정 변경
- [ ] GPS 정확도 부족 및 서비스 비활성 상태
- [ ] 가속도계·자이로 수집 시작과 5초 청크 생성
- [ ] Navigator/Game 20회 전환 중 동일 세션과 수집기 유지
- [ ] 화면 잠금과 복귀
- [ ] 앱 inactive/background/active 전환
- [ ] 비정상 종료 후 세션과 미전송 데이터 복원
- [ ] 네트워크 단절 후 ACK 순서 복구
- [ ] 배터리 사용량과 발열
- [ ] 30분 이상 장시간 주행
- [ ] 순간 GPS 점프와 터널/도심 음영 구간
- [ ] 비행기 모드에서 암호화 Queue 증가 및 앱 재실행 복원
- [ ] 네트워크 복구 후 순차 ACK와 파일 삭제
- [ ] Keychain 키 유지 및 기기 잠금 상태 Data Protection
- [ ] 100MiB 용량 제한과 저장공간 부족 UI
- [ ] 앱 강제 종료 시 uploading 항목 pending 복원
# Risk layer and warning

- [ ] 실제 API bbox/corridor 응답과 HTTP 304 확인
- [ ] 네트워크 단절 후 route/viewport cache 복원 및 마지막 업데이트 표시 확인
- [ ] 401에서 무한 재시도가 없고 향후 token refresh 경계가 유지되는지 확인
- [ ] 평행도로와 반대 방향 주행에서 오경고 여부 확인
- [ ] 교차로, 저속, 고속에서 warning distance 확인
- [ ] GPS 흔들림 중 동일 cell 경고가 cooldown 내 반복되지 않는지 확인
- [ ] Navigator/Game 전환 중 high warning이 animation보다 우선하는지 확인
- [ ] reroute 후 Route/Turn/Current Location layer 유지와 Risk layer 교체 확인
- [ ] background/foreground 후 stale cache refresh 확인
- [ ] 2시간 이상 주행에서 Risk sync, cache 크기, 배터리와 메모리 확인
