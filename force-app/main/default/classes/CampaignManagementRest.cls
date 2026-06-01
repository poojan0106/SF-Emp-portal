/**
 * ✅ EXISTING CAMPAIGN FLOW
 * 1. Display list of active campaigns
 * 2. Allow selection of one campaign
 * 3. Select campaign member status
 * 4. Validate selection before submission
 * 5. Add candidates to selected campaign
 */

@RestResource(urlMapping='/campaigns/*')
global class CampaignManagementRest {
    
    
   
    // ========== METHOD 1: DISPLAY CAMPAIGNS ==========
    
    /**
     * ✅ GET /campaigns
     * Displays list of active campaigns for employer's account
     * 
     * Response: List of campaigns that user can select from
     */
    
    // ========== METHOD 2: ADD TO SELECTED CAMPAIGN ==========
    
    /**
     * ✅ POST /campaigns/add-to-existing
     * 
     * Requirements:
     * 1. Allow selection of one campaign
     * 2. Select campaign member status
     * 3. Validate selection before submission
     * 4. Add candidates to selected campaign
     * 
     * Request Body:
     * {
     *   "candidateIds": ["0031q000001XYZ", "0031q000001ABC"],
     *   "campaignId": "7011q000001XYZAA4",  ← REQUIRED: Selected campaign
     *   "status": "Interested"               ← REQUIRED: Member status
     * }
     */
    


//Test

// ========== REQUEST/RESPONSE CLASSES ==========

/**
 * ✅ Request wrapper - Add to Existing Campaign
 */
public class AddToExistingCampaignRequest {
    public List<Id> candidateIds;      // ✅ REQUIRED: Selected candidates
    public String campaignId;          // ✅ REQUIRED: Selected campaign
    public String status;              // ✅ REQUIRED: Campaign member status
}

/**
 * ✅ Response - Campaign list for dropdown
 */
public class GetCampaignsResponse {
    public List<CampaignOption> campaigns;
    public Integer totalCount;
    public String message;
}

/**
 * ✅ Campaign option for selection
 */
public class CampaignOption {
    public String campaignId;
    public String campaignName;
    public String description;
    public Date startDate;
    public String status;
}

/**
 * ✅ Response - Add to campaign result
 */
public class AddToCampaignResponse {
    public String campaignId;
    public String campaignName;
    public Integer totalProcessed;
    public Integer successCount;
    public Integer failureCount;
    public Integer alreadyMemberCount;
    public List<AddToCampaignResult> campaignResults;
    public String status;
    public String message;
}

/**
 * ✅ Individual result for each candidate
 */
public class AddToCampaignResult {
    public String candidateId;
    public String candidateName;
    public String campaignMemberId;
    public Boolean success;
    public String message;
}

/**
 * ✅ Error response wrapper
 */
public class ErrorResponse {
    public String error;
    
    public ErrorResponse(String message) {
        this.error = message;
    }
}
}