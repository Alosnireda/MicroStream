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

      ;; Public functions
      (define-public (create-channel (creator principal) (deposit uint))
        (let
          ((channel-id (var-get next-channel-id))
           (sender tx-sender))

          ;; Validate creator principal
          (asserts! (validate-creator creator) ERR-INVALID-CREATOR)

          ;; Standard checks
          (asserts! (> deposit u0) ERR-INVALID-AMOUNT)
          (asserts! (is-none (get-channel channel-id)) ERR-ALREADY-EXISTS)
          (asserts! (>= (stx-get-balance sender) deposit) ERR-INSUFFICIENT-BALANCE)

          ;; Transfer deposit to contract
          (try! (stx-transfer? deposit sender (as-contract tx-sender)))

          ;; Create channel
          (map-set channels
            { channel-id: channel-id }
            {
              viewer: sender,
              creator: creator,
              viewer-balance: deposit,
              creator-balance: u0,
              total-deposit: deposit,
              nonce: u0,
              timeout-height: (+ block-height u1440), ;; 24 hour timeout
              is-active: true
            })

          ;; Store initial state
          (map-set channel-states
            { channel-id: channel-id, nonce: u0 }
            {
              viewer-balance: deposit,
              creator-balance: u0,
              viewer-sig: none,
              creator-sig: none
            })

          ;; Increment channel ID
          (var-set next-channel-id (+ channel-id u1))
          (ok channel-id)))

(define-public (propose-update
    (channel-id uint)
    (nonce uint)
    (viewer-balance uint)
    (creator-balance uint)
    (signature (buff 65)))
  (let
    ((channel (unwrap! (get-channel channel-id) ERR-CHANNEL-NOT-FOUND))
     (sender tx-sender))

    ;; Validate signature
    (asserts! (is-valid-signature signature) ERR-INVALID-SIG)

    ;; Validate nonce
    (asserts! (is-valid-nonce channel-id nonce) ERR-INVALID-NONCE)

    ;; Verify channel is active
    (asserts! (get is-active channel) ERR-CHANNEL-CLOSED)

    ;; Verify balances match total deposit
    (asserts! (is-eq (+ viewer-balance creator-balance) 
                     (get total-deposit channel)) ERR-INVALID-AMOUNT)

    ;; Store proposed state with signature
    (map-set channel-states
      { channel-id: channel-id, nonce: nonce }
      {
        viewer-balance: viewer-balance,
        creator-balance: creator-balance,
        viewer-sig: (if (is-eq sender (get viewer channel)) 
                     (some signature)
                     none),
        creator-sig: (if (is-eq sender (get creator channel))
                     (some signature)
                     none)
      })
    (ok true)))

(define-public (accept-update
    (channel-id uint)
    (nonce uint)
    (signature (buff 65)))
  (let
    ((channel (unwrap! (get-channel channel-id) ERR-CHANNEL-NOT-FOUND))
     (state (unwrap! (get-channel-state channel-id nonce) ERR-INVALID-STATE))
     (sender tx-sender))

    ;; Validate signature and nonce
    (asserts! (is-valid-signature signature) ERR-INVALID-SIG)
    (asserts! (is-valid-nonce channel-id nonce) ERR-INVALID-NONCE)

    ;; Verify channel is active
    (asserts! (get is-active channel) ERR-CHANNEL-CLOSED)

    ;; Update signatures based on sender
    (if (is-eq sender (get viewer channel))
      (map-set channel-states
        { channel-id: channel-id, nonce: nonce }
        (merge state { viewer-sig: (some signature) }))
      (map-set channel-states
        { channel-id: channel-id, nonce: nonce }
        (merge state { creator-sig: (some signature) })))

    ;; Check if both signatures are present
    (let ((updated-state (unwrap! (get-channel-state channel-id nonce) ERR-INVALID-STATE)))
      (match (get viewer-sig updated-state)
        viewer-sig 
        (match (get creator-sig updated-state)
          creator-sig
          (begin
            ;; Update channel state
            (map-set channels
              { channel-id: channel-id }
              (merge channel {
                viewer-balance: (get viewer-balance updated-state),
                creator-balance: (get creator-balance updated-state),
                nonce: nonce
              }))
            (ok true))
          ERR-INVALID-STATE)
        ERR-INVALID-STATE))))

(define-public (close-channel (channel-id uint))
  (let
    ((channel (unwrap! (get-channel channel-id) ERR-CHANNEL-NOT-FOUND)))

    ;; Verify channel is active
    (asserts! (get is-active channel) ERR-CHANNEL-CLOSED)

    ;; Verify caller is participant
    (asserts! (or
                (is-eq tx-sender (get viewer channel))
                (is-eq tx-sender (get creator channel)))
              ERR-NOT-AUTHORIZED)

    ;; Transfer balances
    (try! (as-contract 
      (stx-transfer? (get viewer-balance channel) tx-sender (get viewer channel))))
    (try! (as-contract 
      (stx-transfer? (get creator-balance channel) tx-sender (get creator channel))))

    ;; Close channel
    (map-set channels
      { channel-id: channel-id }
      (merge channel { is-active: false }))
    (ok true)))

(define-public (dispute-channel (channel-id uint))
  (let
    ((channel (unwrap! (get-channel channel-id) ERR-CHANNEL-NOT-FOUND)))

    ;; Verify channel is active
    (asserts! (get is-active channel) ERR-CHANNEL-CLOSED)

    ;; Verify caller is participant
    (asserts! (or
                (is-eq tx-sender (get viewer channel))
                (is-eq tx-sender (get creator channel)))
              ERR-NOT-AUTHORIZED)

    ;; Set dispute timeout
    (map-set channels
      { channel-id: channel-id }
      (merge channel
        {
          timeout-height: (+ block-height u1440) ;; 24 hour dispute period
        }))
    (ok true)))

(define-public (settle-disputed-channel (channel-id uint))
  (let
    ((channel (unwrap! (get-channel channel-id) ERR-CHANNEL-NOT-FOUND)))

    ;; Verify channel is active
    (asserts! (get is-active channel) ERR-CHANNEL-CLOSED)

    ;; Verify timeout has passed
    (asserts! (>= block-height (get timeout-height channel))
              ERR-INVALID-STATE)

    ;; Transfer balances
    (try! (as-contract 
      (stx-transfer? (get viewer-balance channel) tx-sender (get viewer channel))))
    (try! (as-contract 
      (stx-transfer? (get creator-balance channel) tx-sender (get creator channel))))

    ;; Close channel
    (map-set channels
      { channel-id: channel-id }
      (merge channel { is-active: false }))
    (ok true)))

