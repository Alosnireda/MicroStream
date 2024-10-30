;; Constants 
(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-ALREADY-EXISTS (err u2))
(define-constant ERR-INVALID-AMOUNT (err u3))
(define-constant ERR-CHANNEL-NOT-FOUND (err u4))
(define-constant ERR-CHANNEL-CLOSED (err u5))
(define-constant ERR-INVALID-SIGNATURE (err u6))
(define-constant ERR-EXPIRED-TIMEOUT (err u7))
(define-constant ERR-INVALID-STATE (err u8))
(define-constant ERR-INSUFFICIENT-BALANCE (err u9))
(define-constant ERR-INVALID-UPDATE (err u10))
(define-constant ERR-INVALID-CREATOR (err u11))
(define-constant ERR-INVALID-NONCE (err u12))
(define-constant ERR-INVALID-SIG (err u13))

;; Data Variables
(define-map channels
  { channel-id: uint }
  {
    viewer: principal,
    creator: principal,
    viewer-balance: uint,
    creator-balance: uint,
    total-deposit: uint,
    nonce: uint,
    timeout-height: uint,
    is-active: bool
  })

(define-data-var next-channel-id uint u0)

(define-map channel-states
  { 
    channel-id: uint,
    nonce: uint 
  }
  {
    viewer-balance: uint,
    creator-balance: uint,
    viewer-sig: (optional (buff 65)),
    creator-sig: (optional (buff 65))
  })

  ;; Read-only functions
  (define-read-only (get-channel (channel-id uint))
    (map-get? channels { channel-id: channel-id }))

  (define-read-only (get-channel-state (channel-id uint) (nonce uint))
    (map-get? channel-states { channel-id: channel-id, nonce: nonce }))

  (define-read-only (get-current-nonce (channel-id uint))
    (match (get-channel channel-id)
      channel (get nonce channel)
      u0))

  ;; Private helper functions
  (define-private (is-valid-signature (sig (buff 65)))
    (and 
      (is-eq (len sig) u65)
      (is-ok (secp256k1-recover? 0x0000000000000000000000000000000000000000000000000000000000000000 sig))))

  (define-private (is-valid-nonce (channel-id uint) (nonce uint))
    (match (get-channel channel-id)
      channel (is-eq nonce (+ (get nonce channel) u1))
      false))

  (define-private (validate-creator (creator principal))
    (and 
      (not (is-eq creator tx-sender))
      (not (is-eq creator (as-contract tx-sender)))))

      