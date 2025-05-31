;; CodeCatalyst - Decentralized Open Source Project Funding Platform
;; Empowering developers to build the future, one project at a time

;; Error codes
(define-constant ERR-ACCESS-DENIED (err u1))
(define-constant ERR-VENTURE-NOT-FOUND (err u2))
(define-constant ERR-VENTURE-CLOSED (err u3))
(define-constant ERR-WALLET-INSUFFICIENT (err u4))
(define-constant ERR-AMOUNT-INVALID (err u5))
(define-constant ERR-CHECKPOINT-NOT-FOUND (err u6))
(define-constant ERR-CHECKPOINT-PENDING (err u7))
(define-constant ERR-TITLE-INVALID (err u8))
(define-constant ERR-DESCRIPTION-INVALID (err u9))
(define-constant ERR-CHECKPOINT-TITLE-INVALID (err u10))
(define-constant ERR-CHECKPOINT-DESC-INVALID (err u11))
(define-constant ERR-DEADLINE-INVALID (err u12))
(define-constant ERR-VENTURE-ID-INVALID (err u13))
(define-constant ERR-CHECKPOINT-ID-INVALID (err u14))
(define-constant ERR-VENTURE-ALREADY-EXISTS (err u15))

;; Data variables
(define-data-var platform-admin principal tx-sender)
(define-map code-ventures 
    { venture-id: uint }
    {
        creator: principal,
        title: (string-ascii 100),
        description: (string-utf8 500),
        funding-goal: uint,
        raised-amount: uint,
        status: (string-ascii 20),
        launch-block: uint,
        category: (string-ascii 50)
    }
)

(define-map venture-checkpoints
    { venture-id: uint, checkpoint-id: uint }
    {
        title: (string-ascii 100),
        description: (string-utf8 500),
        deadline: uint,
        reward-amount: uint,
        status: (string-ascii 20),
        deliverable-url: (string-utf8 200)
    }
)

(define-map backer-contributions
    { venture-id: uint, backer: principal }
    { amount: uint, backing-block: uint }
)

(define-map venture-categories
    { category-name: (string-ascii 50) }
    { venture-count: uint, total-funding: uint }
)

;; Counter for venture IDs
(define-data-var next-venture-id uint u1)

;; Platform stats
(define-data-var total-platform-funding uint u0)
(define-data-var active-ventures-count uint u0)

;; Helper functions for validation
(define-private (valid-ascii-string (value (string-ascii 100)))
    (> (len value) u0)
)

(define-private (valid-utf8-string (value (string-utf8 500)))
    (> (len value) u0)
)

(define-private (valid-venture-id (id uint))
    (and 
        (> id u0)
        (< id (var-get next-venture-id))
    )
)

(define-private (valid-checkpoint-id (id uint))
    (> id u0)
)

(define-private (valid-deadline (deadline uint))
    (> deadline block-height)
)

(define-private (valid-category (category (string-ascii 50)))
    (and 
        (> (len category) u0)
        (<= (len category) u50)
    )
)

;; Initialize platform
(define-public (initialize-platform)
    (begin
        (asserts! (is-eq tx-sender (var-get platform-admin)) ERR-ACCESS-DENIED)
        (var-set total-platform-funding u0)
        (var-set active-ventures-count u0)
        (ok true)
    )
)

;; Launch a new venture
(define-public (launch-venture 
                (title (string-ascii 100)) 
                (description (string-utf8 500))
                (funding-goal uint)
                (category (string-ascii 50)))
    (begin
        ;; Validate inputs
        (asserts! (valid-ascii-string title) ERR-TITLE-INVALID)
        (asserts! (valid-utf8-string description) ERR-DESCRIPTION-INVALID)
        (asserts! (> funding-goal u0) ERR-AMOUNT-INVALID)
        (asserts! (valid-category category) ERR-CHECKPOINT-DESC-INVALID)
        
        (let ((new-venture-id (var-get next-venture-id)))
            ;; Create venture
            (map-insert code-ventures
                { venture-id: new-venture-id }
                {
                    creator: tx-sender,
                    title: title,
                    description: description,
                    funding-goal: funding-goal,
                    raised-amount: u0,
                    status: "active",
                    launch-block: block-height,
                    category: category
                }
            )
            
            ;; Update category stats
            (match (map-get? venture-categories { category-name: category })
                existing-category 
                (map-set venture-categories
                    { category-name: category }
                    { 
                        venture-count: (+ (get venture-count existing-category) u1),
                        total-funding: (get total-funding existing-category)
                    }
                )
                (map-insert venture-categories
                    { category-name: category }
                    { venture-count: u1, total-funding: u0 }
                )
            )
            
            ;; Update counters
            (var-set next-venture-id (+ new-venture-id u1))
            (var-set active-ventures-count (+ (var-get active-ventures-count) u1))
            (ok new-venture-id)
        )
    )
)

;; Add checkpoint to venture
(define-public (create-checkpoint 
                (venture-id uint)
                (title (string-ascii 100))
                (description (string-utf8 500))
                (deadline uint)
                (reward-amount uint)
                (deliverable-url (string-utf8 200)))
    (begin
        ;; Validate inputs
        (asserts! (valid-venture-id venture-id) ERR-VENTURE-ID-INVALID)
        (asserts! (valid-ascii-string title) ERR-CHECKPOINT-TITLE-INVALID)
        (asserts! (valid-utf8-string description) ERR-CHECKPOINT-DESC-INVALID)
        (asserts! (valid-deadline deadline) ERR-DEADLINE-INVALID)
        
        (let ((venture-data (unwrap! (map-get? code-ventures { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND)))
            (asserts! (is-eq (get creator venture-data) tx-sender) ERR-ACCESS-DENIED)
            (asserts! (<= reward-amount (get funding-goal venture-data)) ERR-AMOUNT-INVALID)
            
            (map-insert venture-checkpoints
                { 
                    venture-id: venture-id,
                    checkpoint-id: u1
                }
                {
                    title: title,
                    description: description,
                    deadline: deadline,
                    reward-amount: reward-amount,
                    status: "pending",
                    deliverable-url: deliverable-url
                }
            )
            (ok true)
        )
    )
)

;; Back a venture with funding
(define-public (back-venture (venture-id uint) (amount uint))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-VENTURE-ID-INVALID)
        
        (let (
            (venture-data (unwrap! (map-get? code-ventures { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND))
            (current-funding (get raised-amount venture-data))
            (funding-target (get funding-goal venture-data))
        )
            (asserts! (is-eq (get status venture-data) "active") ERR-VENTURE-CLOSED)
            (asserts! (> amount u0) ERR-AMOUNT-INVALID)
            (asserts! (<= (+ current-funding amount) funding-target) ERR-AMOUNT-INVALID)
            
            ;; Transfer STX to contract
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            
            ;; Update venture funding
            (map-set code-ventures
                { venture-id: venture-id }
                (merge venture-data {
                    raised-amount: (+ current-funding amount)
                })
            )
            
            ;; Update platform stats
            (var-set total-platform-funding (+ (var-get total-platform-funding) amount))
            
            ;; Update category funding
            (let ((category (get category venture-data)))
                (match (map-get? venture-categories { category-name: category })
                    existing-category 
                    (map-set venture-categories
                        { category-name: category }
                        (merge existing-category {
                            total-funding: (+ (get total-funding existing-category) amount)
                        })
                    )
                    false ;; Category should exist if venture exists
                )
            )
            
            ;; Record backer contribution
            (match (map-get? backer-contributions 
                    { venture-id: venture-id, backer: tx-sender })
                previous-backing 
                (map-set backer-contributions
                    { venture-id: venture-id, backer: tx-sender }
                    { 
                        amount: (+ amount (get amount previous-backing)),
                        backing-block: block-height
                    }
                )
                (map-insert backer-contributions
                    { venture-id: venture-id, backer: tx-sender }
                    { amount: amount, backing-block: block-height }
                )
            )
            
            (ok true)
        )
    )
)

;; Complete checkpoint and claim reward
(define-public (complete-checkpoint (venture-id uint) (checkpoint-id uint))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-VENTURE-ID-INVALID)
        (asserts! (valid-checkpoint-id checkpoint-id) ERR-CHECKPOINT-ID-INVALID)
        
        (let (
            (venture-data (unwrap! (map-get? code-ventures 
                { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND))
            (checkpoint-data (unwrap! (map-get? venture-checkpoints 
                { venture-id: venture-id, checkpoint-id: checkpoint-id }) 
                ERR-CHECKPOINT-NOT-FOUND))
        )
            (asserts! (is-eq (get creator venture-data) tx-sender) ERR-ACCESS-DENIED)
            (asserts! (>= block-height (get deadline checkpoint-data)) ERR-CHECKPOINT-PENDING)
            
            ;; Update checkpoint status
            (map-set venture-checkpoints
                { venture-id: venture-id, checkpoint-id: checkpoint-id }
                (merge checkpoint-data { status: "completed" })
            )
            
            ;; Transfer reward to creator
            (try! (as-contract (stx-transfer? 
                (get reward-amount checkpoint-data) 
                tx-sender 
                (get creator venture-data))))
            
            (ok true)
        )
    )
)

;; NEW FUNCTION: Get trending ventures by category
(define-public (get-trending-ventures (category (string-ascii 50)) (limit uint))
    (begin
        (asserts! (valid-category category) ERR-CHECKPOINT-DESC-INVALID)
        (asserts! (<= limit u10) ERR-AMOUNT-INVALID) ;; Limit to prevent too many results
        
        ;; This is a simplified version - in a full implementation, 
        ;; you'd want to iterate through ventures and filter by category
        (ok (map-get? venture-categories { category-name: category }))
    )
)

;; Read-only functions
;; Get venture details
(define-read-only (get-venture-info (venture-id uint))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-VENTURE-ID-INVALID)
        (ok (unwrap! (map-get? code-ventures 
            { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND))
    )
)

;; Get checkpoint details
(define-read-only (get-checkpoint-info (venture-id uint) (checkpoint-id uint))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-VENTURE-ID-INVALID)
        (asserts! (valid-checkpoint-id checkpoint-id) ERR-CHECKPOINT-ID-INVALID)
        (ok (unwrap! (map-get? venture-checkpoints 
            { venture-id: venture-id, checkpoint-id: checkpoint-id }) 
            ERR-CHECKPOINT-NOT-FOUND))
    )
)

;; Get total ventures launched
(define-read-only (get-total-ventures)
    (ok (- (var-get next-venture-id) u1))
)

;; Get backer contribution amount
(define-read-only (get-backer-info (venture-id uint) (backer principal))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-VENTURE-ID-INVALID)
        (ok (unwrap! (map-get? backer-contributions 
            { venture-id: venture-id, backer: backer }) 
            ERR-VENTURE-NOT-FOUND))
    )
)

;; Check if venture reached funding goal
(define-read-only (is-venture-funded (venture-id uint))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-VENTURE-ID-INVALID)
        (match (map-get? code-ventures { venture-id: venture-id })
            venture-data (ok (>= (get raised-amount venture-data) 
                               (get funding-goal venture-data)))
            ERR-VENTURE-NOT-FOUND
        )
    )
)

;; Check if checkpoint is completed
(define-read-only (is-checkpoint-done (venture-id uint) (checkpoint-id uint))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-VENTURE-ID-INVALID)
        (asserts! (valid-checkpoint-id checkpoint-id) ERR-CHECKPOINT-ID-INVALID)
        (match (map-get? venture-checkpoints 
            { venture-id: venture-id, checkpoint-id: checkpoint-id })
            checkpoint-data (ok (is-eq (get status checkpoint-data) "completed"))
            ERR-CHECKPOINT-NOT-FOUND
        )
    )
)

;; Get platform statistics
(define-read-only (get-platform-stats)
    (ok {
        total-funding: (var-get total-platform-funding),
        active-ventures: (var-get active-ventures-count),
        total-ventures: (- (var-get next-venture-id) u1)
    })
)

;; Get category statistics
(define-read-only (get-category-stats (category (string-ascii 50)))
    (begin
        (asserts! (valid-category category) ERR-CHECKPOINT-DESC-INVALID)
        (ok (unwrap! (map-get? venture-categories { category-name: category }) 
            ERR-VENTURE-NOT-FOUND))
    )
)