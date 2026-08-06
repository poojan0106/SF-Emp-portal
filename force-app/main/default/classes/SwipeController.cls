/**
 * ═══════════════════════════════════════════════════════════════════════════
 * SwipeController.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: REST API Entry Point for all Swipe Interface operations
 * 
 * TASKS COVERED:
 *   - US-041-BE-009: Create SwipeController.cls Apex REST class
 *   - US-041-BE-010: Build getNextEmployers() endpoint
 *   - US-041-BE-013: Build recordSwipe() endpoint
 *   - US-041-BE-018: Create undoSwipe() endpoint
 *   - US-041-BE-019: Build undo time window validation
 *   - US-041-BE-020: Create saveSentiment() endpoint
 * 
 * ENDPOINTS:
 *   GET  /api/swipe/employers  → Get next batch of employer cards
 *   GET  /api/swipe/session    → Get current session status
 *   POST /api/swipe/record     → Record a swipe (right/left)
 *   POST /api/swipe/undo       → Undo last swipe (30s window)
 *   POST /api/swipe/sentiment  → Save sentiment feedback
 *   POST /api/swipe/session    → Start new session
 * 
 * FIX APPLIED: Changed from returning inner class to void methods with
 *              manual JSON serialization via RestContext.response
 *              (Salesforce limitation: @HttpGet/@HttpPost cannot return inner classes)
 * 
 * CHANGES (v2):
 *   - GET /employers + GET /session: read candidateId from req.params (query string)
 *     instead of req.requestBody (GET requests carry no body)
 *   - POST /record: added candidateId to SwipeRequest DTO; removed hardcoded ID
 *   - POST /undo: added candidateId to UndoRequest DTO; removed hardcoded ID
 *   - POST /sentiment: added candidateId to SentimentRequest DTO; removed hardcoded ID
 *   - POST /session: added SessionStartRequest DTO with candidateId; removed hardcoded ID
 *   - Removed getCurrentCandidateId() — all callers now read from the request payload
 * 
 * AUTHOR: [Vijay Rathore]
 * DATE: January 2025
 * ═══════════════════════════════════════════════════════════════════════════
 */
@RestResource(urlMapping='/api/swipe/*')
global with sharing class SwipeController {
    
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS - Business Rules Configuration
    // ═══════════════════════════════════════════════════════════════════════
    
    private static final Integer MAX_SWIPES_PER_SESSION = 20;
    private static final Integer UNDO_WINDOW_SECONDS    = 30;
    private static final Integer EMPLOYER_BATCH_SIZE    = 10;
    private static final Integer SWIPE_COOLDOWN_DAYS    = 180;
    
    // ═══════════════════════════════════════════════════════════════════════
    // HTTP GET Handler
    // FIX: candidateId now read from query params (req.params), not body.
    //      GET requests have no body — reading req.requestBody always returns null.
    // ═══════════════════════════════════════════════════════════════════════
    
    @HttpGet
    global static void doGet() {
        RestRequest  req      = RestContext.request;
        String       endpoint = req.requestURI.substringAfterLast('/');
        
        try {
            if (endpoint == 'employers') {
                // JS sends: GET /employers?candidateId=<id>
                String candidateId = req.params.get('candidateId');
                if (String.isBlank(candidateId)) {
                    sendResponse(400, false, 'candidateId query param is required', null);
                    return;
                }
                getNextEmployers(candidateId);

            } else if (endpoint == 'session') {
                // JS sends: GET /session?candidateId=<id>
                String candidateId = req.params.get('candidateId');
                if (String.isBlank(candidateId)) {
                    sendResponse(400, false, 'candidateId query param is required', null);
                    return;
                }
                getSessionStatus(candidateId);

            } else {
                sendResponse(400, false, 'Invalid endpoint: ' + endpoint, null);
            }
        } catch (Exception e) {
            sendResponse(500, false, 'Server error: ' + e.getMessage(), null);
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // HTTP POST Handler
    // ═══════════════════════════════════════════════════════════════════════
    
    @HttpPost
    global static void doPost() {
        RestRequest req         = RestContext.request;
        String      endpoint    = req.requestURI.substringAfterLast('/');
        String      requestBody = req.requestBody != null ? req.requestBody.toString() : '{}';
        
        try {
            if (endpoint == 'record') {
                recordSwipe(requestBody);
            } else if (endpoint == 'undo') {
                undoSwipe(requestBody);
            } else if (endpoint == 'sentiment') {
                saveSentiment(requestBody);
            } else if (endpoint == 'session') {
                startNewSession(requestBody);
            } else {
                sendResponse(400, false, 'Invalid endpoint: ' + endpoint, null);
            }
        } catch (Exception e) {
            sendResponse(500, false, 'Server error: ' + e.getMessage(), null);
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Response Helper
    // ═══════════════════════════════════════════════════════════════════════
    
    private static void sendResponse(Integer statusCode, Boolean success, String message, Map<String, Object> data) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        
        Map<String, Object> responseBody = new Map<String, Object>{
            'success' => success,
            'message' => message,
            'data'    => data
        };
        
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(responseBody));
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TASK US-041-BE-010: getNextEmployers()
    // ═══════════════════════════════════════════════════════════════════════
    
    private static void getNextEmployers(String cId) {
        Id candidateId;
        try {
            candidateId = Id.valueOf(cId);
        } catch (Exception e) {
            sendResponse(400, false, 'Invalid candidateId', null);
            return;
        }
        
        SessionStatus sessionStatus = SwipeSessionService.getSessionStatus(candidateId);
        
        if (sessionStatus.limitReached) {
            Map<String, Object> data = new Map<String, Object>{
                'employers'     => new List<EmployerCard>(),
                'sessionStatus' => sessionStatus,
                'hasMore'       => false,
                'message'       => 'You\'ve reached your daily swipe limit. Come back tomorrow!'
            };
            sendResponse(200, true, 'Session limit reached', data);
            return;
        }
        
        List<EmployerCard> employers = EmployerMatchingService.getMatchingEmployers(
            candidateId, 
            EMPLOYER_BATCH_SIZE
        );
        
        Map<String, Object> data = new Map<String, Object>{
            'employers'     => employers,
            'sessionStatus' => sessionStatus,
            'hasMore'       => employers.size() == EMPLOYER_BATCH_SIZE
        };
        
        sendResponse(200, true, 'Success', data);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TASK US-041-BE-013: recordSwipe()
    // FIX: SwipeRequest now carries candidateId; hardcoded method removed.
    // ═══════════════════════════════════════════════════════════════════════
    
    private static void recordSwipe(String requestBody) {
        SwipeRequest swipeReq;
        System.debug('Request Body++++' + requestBody);
        try {
            swipeReq = (SwipeRequest) JSON.deserialize(requestBody, SwipeRequest.class);
        } catch (Exception e) {
            sendResponse(400, false, 'Invalid request format', null);
            return;
        }
        
        if (String.isBlank(swipeReq.candidateId) || swipeReq.employerId == null || String.isBlank(swipeReq.direction)) {
            sendResponse(400, false, 'candidateId, employerId and direction are required', null);
            return;
        }
        
        if (swipeReq.direction != 'Right' && swipeReq.direction != 'Left') {
            sendResponse(400, false, 'direction must be "Right" or "Left"', null);
            return;
        }
        
        Id candidateId;
        try {
            candidateId = Id.valueOf(swipeReq.candidateId);
        } catch (Exception e) {
            sendResponse(400, false, 'Invalid candidateId', null);
            return;
        }
        
        SessionStatus sessionStatus = SwipeSessionService.getSessionStatus(candidateId);
        if (sessionStatus.limitReached) {
            sendResponse(429, false, 'Session limit reached. Maximum ' + MAX_SWIPES_PER_SESSION + ' swipes per session.', 
                new Map<String, Object>{'sessionStatus' => sessionStatus});
            return;
        }
        
        Swipe_Event__c swipeEvent = new Swipe_Event__c(
            Candidate__c  = candidateId,
            Employers__c  = swipeReq.employerId,
            Direction__c  = swipeReq.direction,
            Timestamp__c  = DateTime.now(),
            Session_ID__c = sessionStatus.sessionId,
            Is_Undone__c  = false
        );
        
        try {
            insert swipeEvent;
        } catch (DmlException e) {
            sendResponse(500, false, 'Failed to record swipe: ' + e.getMessage(), null);
            return;
        }
        
        SwipeSessionService.incrementSwipeCount(candidateId);
        sessionStatus = SwipeSessionService.getSessionStatus(candidateId);
        
        Map<String, Object> data = new Map<String, Object>{
            'swipeEventId'     => swipeEvent.Id,
            'sessionStatus'    => sessionStatus,
            'requiresSentiment'=> swipeReq.direction == 'Right'
        };
        
        sendResponse(200, true, 'Swipe recorded successfully', data);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TASK US-041-BE-018 & BE-019: undoSwipe()
    // FIX: UndoRequest now carries candidateId; hardcoded method removed.
    // ═══════════════════════════════════════════════════════════════════════
    
    private static void undoSwipe(String requestBody) {
        UndoRequest undoReq;
        try {
            undoReq = (UndoRequest) JSON.deserialize(requestBody, UndoRequest.class);
        } catch (Exception e) {
            sendResponse(400, false, 'Invalid request format', null);
            return;
        }
        
        if (undoReq.swipeEventId == null || String.isBlank(undoReq.candidateId)) {
            sendResponse(400, false, 'swipeEventId and candidateId are required', null);
            return;
        }
        
        Id candidateId;
        try {
            candidateId = Id.valueOf(undoReq.candidateId);
        } catch (Exception e) {
            sendResponse(400, false, 'Invalid candidateId', null);
            return;
        }
        
        List<Swipe_Event__c> swipes = [
            SELECT Id, Timestamp__c, Is_Undone__c, Direction__c, Employers__c
            FROM   Swipe_Event__c
            WHERE  Id = :undoReq.swipeEventId
            AND    Candidate__c = :candidateId
            AND    Is_Undone__c = false
            LIMIT  1
        ];
        
        if (swipes.isEmpty()) {
            sendResponse(404, false, 'Swipe event not found or already undone', null);
            return;
        }
        
        Swipe_Event__c swipe = swipes[0];
        
        // TASK US-041-BE-019 - Validate 30-second undo window
        Long millisSinceSwipe  = DateTime.now().getTime() - swipe.Timestamp__c.getTime();
        Long secondsSinceSwipe = millisSinceSwipe / 1000;
        
        if (secondsSinceSwipe > UNDO_WINDOW_SECONDS) {
            sendResponse(410, false, 
                'Undo window expired. Swipes can only be undone within ' + UNDO_WINDOW_SECONDS + ' seconds. ' +
                'Time elapsed: ' + secondsSinceSwipe + ' seconds.', 
                null);
            return;
        }
        
        swipe.Is_Undone__c    = true;
        swipe.Undo_Timestamp__c = DateTime.now();
        
        try {
            update swipe;
        } catch (DmlException e) {
            sendResponse(500, false, 'Failed to undo swipe: ' + e.getMessage(), null);
            return;
        }
        
        SwipeSessionService.decrementSwipeCount(candidateId);
        
        List<Employer_Sentiment__c> sentiments = [
            SELECT Id FROM Employer_Sentiment__c 
            WHERE Swipe_Event__c = :swipe.Id
        ];
        if (!sentiments.isEmpty()) {
            delete sentiments;
        }
        
        if (swipe.Direction__c == 'Right') {
            TalentPoolService.removeCandidateFromPool(candidateId, swipe.Employers__c);
        }
        
        Map<String, Object> data = new Map<String, Object>{
            'undoneSwipeId' => swipe.Id,
            'employerId'    => swipe.Employers__c,
            'sessionStatus' => SwipeSessionService.getSessionStatus(candidateId)
        };
        
        sendResponse(200, true, 'Swipe undone successfully', data);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TASK US-041-BE-020: saveSentiment()
    // FIX: SentimentRequest now carries candidateId; hardcoded method removed.
    // ═══════════════════════════════════════════════════════════════════════
    
    private static void saveSentiment(String requestBody) {
        SentimentRequest sentReq;
        try {
            sentReq = (SentimentRequest) JSON.deserialize(requestBody, SentimentRequest.class);
        } catch (Exception e) {
            sendResponse(400, false, 'Invalid request format', null);
            return;
        }
        
        if (sentReq.swipeEventId == null || String.isBlank(sentReq.candidateId)) {
            sendResponse(400, false, 'swipeEventId and candidateId are required', null);
            return;
        }
        
        Id candidateId;
        try {
            candidateId = Id.valueOf(sentReq.candidateId);
        } catch (Exception e) {
            sendResponse(400, false, 'Invalid candidateId', null);
            return;
        }
        
        List<Swipe_Event__c> swipes = [
            SELECT Id, Employers__c, Direction__c
            FROM   Swipe_Event__c
            WHERE  Id = :sentReq.swipeEventId
            AND    Candidate__c = :candidateId
            AND    Is_Undone__c = false
            LIMIT  1
        ];
        
        if (swipes.isEmpty()) {
            sendResponse(404, false, 'Swipe event not found', null);
            return;
        }
        
        Swipe_Event__c swipe = swipes[0];
        
        Employer_Sentiment__c sentiment = SentimentService.createSentiment(
            candidateId,
            swipe.Employers__c,
            sentReq.swipeEventId,
            swipe.Direction__c,
            sentReq.signals != null ? sentReq.signals : new List<String>(),
            sentReq.freeText
        );
        
        sendResponse(200, true, 'Sentiment saved successfully', 
            new Map<String, Object>{'sentimentId' => sentiment.Id});
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Session Management
    // FIX: startNewSession now accepts body with candidateId.
    //      getSessionStatus now accepts candidateId param from query string.
    // ═══════════════════════════════════════════════════════════════════════
    
    private static void startNewSession(String requestBody) {
        SessionStartRequest startReq;
        try {
            startReq = (SessionStartRequest) JSON.deserialize(requestBody, SessionStartRequest.class);
        } catch (Exception e) {
            sendResponse(400, false, 'Invalid request format', null);
            return;
        }
        
        if (String.isBlank(startReq.candidateId)) {
            sendResponse(400, false, 'candidateId is required', null);
            return;
        }
        
        Id candidateId;
        try {
            candidateId = Id.valueOf(startReq.candidateId);
        } catch (Exception e) {
            sendResponse(400, false, 'Invalid candidateId', null);
            return;
        }
        
        SessionStatus session = SwipeSessionService.startNewSession(candidateId);
        sendResponse(200, true, 'New session started', 
            new Map<String, Object>{'sessionStatus' => session});
    }
    
    private static void getSessionStatus(String cId) {
        Id candidateId;
        try {
            candidateId = Id.valueOf(cId);
        } catch (Exception e) {
            sendResponse(400, false, 'Invalid candidateId', null);
            return;
        }
        
        SessionStatus session = SwipeSessionService.getSessionStatus(candidateId);
        sendResponse(200, true, 'Session status retrieved', 
            new Map<String, Object>{'sessionStatus' => session});
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Inner Classes - Request DTOs
    // ═══════════════════════════════════════════════════════════════════════
    
    // FIX: candidateId added — JS sends it in the POST body for all three
    global class SwipeRequest {
        public String candidateId;   // added
        public String employerId;
        public String direction;
    }
    
    global class UndoRequest {
        public String candidateId;   // added (was missing; JS sends it)
        public Id     swipeEventId;
    }
    
    global class SentimentRequest {
        public String       candidateId;  // added
        public Id           swipeEventId;
        public List<String> signals;
        public String       freeText;
    }
    
    // FIX: new DTO for POST /session (JS sends { candidateId })
    global class SessionStartRequest {
        public String candidateId;
    }
    
    global class SessionStatus {
        public String   sessionId;
        public Integer  swipeCount;
        public Integer  maxSwipes;
        public Boolean  limitReached;
        public Integer  remainingSwipes;
        public DateTime sessionStarted;
    }
    
    global class EmployerCard {
        public Id           employerId;
        public String       name;
        public String       logoUrl;
        public String       industry;
        public String       employeeCount;
        public String       description;
        public String       companyCulture;
        public String       companySize;
        public String       remoteWorkPolicy;
        public String       whyJoin;
        public List<String> highlights;
        public List<String> values;
        public String       typicalRoles;
        public Decimal      sentimentScore;
        public String       salaryRange;
        public Boolean      hasMatchingRoles;
    }
}