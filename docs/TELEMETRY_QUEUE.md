# Encrypted telemetry queue

Production은 Application Support 아래 `R2D/Telemetry`를 사용한다.

```text
Telemetry/
├── queue-index.json
├── chunks/{queue-item-id}.bin
└── quarantine/
```

메타데이터는 atomic JSON index, payload는 파일별 AES-256-GCM combined sealed box다. 키는 `KeychainSecretKeyStore`가 ThisDeviceOnly Keychain 항목으로 생성·보관한다. Preview/Test는 메모리 키와 메모리 Queue를 사용한다.

원본 `SensorChunk` JSON을 암호화하기 전에 SHA-256을 계산하고, 복호화 후 다시 검사한다. metadata/payload 불일치, orphan, 복호화 또는 checksum 실패 데이터는 자동 삭제하지 않고 quarantine한다. 시작 시 `uploading`은 `pending`으로 되돌린다.

중복 기준은 다음 중 하나다.

- `sessionID + chunkSequence`
- `clientEventID`
- `idempotencyKey`

상태는 `pending → uploading → acknowledged → 삭제`다. ACK 전 payload는 삭제하지 않는다. 일시 오류는 `pending`과 `nextRetryAt`으로 돌아가며 영구 오류는 `failed`가 된다.

기본 최대 용량은 100MiB다. 용량 초과 시 미전송 데이터를 삭제하지 않고 새 enqueue를 거부해 storage-full 상태를 노출한다. 완전한 디스크 부족 및 일부 파일 삭제 실패 복구는 실제 기기 fault-injection 검증이 추가로 필요하다.
