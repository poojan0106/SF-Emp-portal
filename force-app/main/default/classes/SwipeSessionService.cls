/**
 * ═══════════════════════════════════════════════════════════════════════════
 * FILE 1: SwipeSessionService.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Manages swipe session lifecycle and enforces limits
 * 
 * TASKS COVERED:
 *   - US-041-BE-016: Implement session tracking
 *   - US-041-BE-017: Build session limit enforcement
 * 
 * SESSION RULES:
 *   - Max 20 swipes per session
 *   - Session expires after 24 hours
 *   - New session auto-created when needed
 * ═══════════════════════════════════════════════════════════════════════════
 */
public with sharing class SwipeSessionService {
    
    /** Maximum swipes allowed per session */
    private static final Integer MAX_SWIPES_PER_SESSION = 20;
    
    /** Hours before session expires and resets */
    private static final Integer SESSION_TIMEOUT_HOURS = 24;
    
    /**
     * Gets the current session status for a candidate.
     * Auto-creates new session if none exists or current is expired.
     * 
     * LOGIC:
     * 1. Query Contact for session fields
     * 2. Check if session exists AND is not expired
     * 3. If invalid → auto-create new session
     * 4. Calculate limit status
     * 5. Return SessionStatus object
     * 
     * @param candidateId The Contact Id of the candidate
     * @return SessionStatus with current session info
     */
    public static SwipeController.SessionStatus getSessionStatus(Id candidateId) {
        // Query current session fields from Contact
        Contact candidate = [
            SELECT Id, 
                   Current_Session_ID__c, 
                   Current_Session_Swipe_Count__c,
                   Session_Started_At__c
            FROM Contact
            WHERE Id = :candidateId
            LIMIT 1
        ];
        
        // Check if session is valid:
        // 1. Session ID exists
        // 2. Session started timestamp exists
        // 3. Session is not older than 24 hours
        Boolean hasValidSession = 
            String.isNotBlank(candidate.Current_Session_ID__c) &&
            candidate.Session_Started_At__c != null &&
            candidate.Session_Started_At__c.addHours(SESSION_TIMEOUT_HOURS) > DateTime.now();
        
        // If no valid session, auto-create new one
        if (!hasValidSession) {
            return startNewSession(candidateId);
        }
        
        // Build session status from existing session
        SwipeController.SessionStatus status = new SwipeController.SessionStatus();
        status.sessionId = candidate.Current_Session_ID__c;
        status.swipeCount = candidate.Current_Session_Swipe_Count__c != null 
                           ? Integer.valueOf(candidate.Current_Session_Swipe_Count__c) 
                           : 0;
        status.maxSwipes = MAX_SWIPES_PER_SESSION;
        status.limitReached = status.swipeCount >= MAX_SWIPES_PER_SESSION;
        status.remainingSwipes = Math.max(0, MAX_SWIPES_PER_SESSION - status.swipeCount);
        status.sessionStarted = candidate.Session_Started_At__c;
        
        return status;
    }
    
    /**
     * Starts a new swipe session for the candidate.
     * Resets swipe count to 0 and generates new session ID.
     * 
     * @param candidateId The Contact Id of the candidate
     * @return SessionStatus for the new session
     */
    public static SwipeController.SessionStatus startNewSession(Id candidateId) {
        String sessionId = generateSessionId();
        DateTime now = DateTime.now();
        
        // Update Contact with new session info
        Contact candidate = new Contact(
            Id = candidateId,
            Current_Session_ID__c = sessionId,
            Current_Session_Swipe_Count__c = 0,
            Session_Started_At__c = now
        );
        update candidate;
        
        // Build and return session status
        SwipeController.SessionStatus status = new SwipeController.SessionStatus();
        status.sessionId = sessionId;
        status.swipeCount = 0;
        status.maxSwipes = MAX_SWIPES_PER_SESSION;
        status.limitReached = false;
        status.remainingSwipes = MAX_SWIPES_PER_SESSION;
        status.sessionStarted = now;
        
        return status;
    }
    
    /**
     * Increments the swipe count for the current session.
     * Called after successfully recording a swipe.
     * 
     * @param candidateId The Contact Id of the candidate
     */
    public static void incrementSwipeCount(Id candidateId) {
        Contact candidate = [
            SELECT Id, Current_Session_Swipe_Count__c
            FROM Contact
            WHERE Id = :candidateId
            LIMIT 1
        ];
        
        Decimal currentCount = candidate.Current_Session_Swipe_Count__c;
        candidate.Current_Session_Swipe_Count__c = (currentCount == null ? 0 : currentCount) + 1;
        
        update candidate;
    }
    
    /**
     * Decrements the swipe count (used for undo operations).
     * Ensures count doesn't go below 0.
     * 
     * @param candidateId The Contact Id of the candidate
     */
    public static void decrementSwipeCount(Id candidateId) {
        Contact candidate = [
            SELECT Id, Current_Session_Swipe_Count__c
            FROM Contact
            WHERE Id = :candidateId
            LIMIT 1
        ];
        
        if (candidate.Current_Session_Swipe_Count__c != null && 
            candidate.Current_Session_Swipe_Count__c > 0) {
            candidate.Current_Session_Swipe_Count__c -= 1;
            update candidate;
        }
    }
    
    /**
     * Generates a unique session ID.
     * Format: {random-hex}-{timestamp}
     * Example: "a1b2c3d4e5f6g7h8-1706123456789"
     */
    private static String generateSessionId() {
        // Generate random bytes and convert to hex
        Blob randomBytes = Crypto.generateAesKey(128);
        String hexString = EncodingUtil.convertToHex(randomBytes);
        
        // Take first 16 characters and append timestamp
        return hexString.substring(0, 16) + '-' + String.valueOf(DateTime.now().getTime());
    }
}