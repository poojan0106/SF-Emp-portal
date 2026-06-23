/**
 * CandidateAPI
 * REST API controller for candidate management
 * Endpoints: /services/apexrest/api/candidates/*
 * 
 * All methods now require accountId parameter for multi-tenant support
 */
@RestResource(urlMapping='/api/candidates/*')
global class CandidateAPI {
    
    /**
     * GET /api/candidates?accountId=xxx or /api/candidates/{id}?accountId=xxx
     * Retrieve candidates list (with pagination/filters) or single candidate details
     */
    @HttpGet
    global static void doGet() {
        try {
            System.debug('=== CandidateAPI.doGet START ===');
            System.debug('Request URI: ' + RestContext.request.requestURI);
            System.debug('Query Params: ' + RestContext.request.params);
            
            RestRequest req = RestContext.request;
            RestResponse res = RestContext.response;
            
            // ✅ Extract accountId from query parameter (REQUIRED)
            String accountIdParam = req.params.get('accountId');
            
            if (String.isBlank(accountIdParam)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('accountId parameter is required')
                ));
                return;
            }
            
            Id accountId;
            try {
                accountId = Id.valueOf(accountIdParam);
            } catch (Exception e) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('Invalid accountId format')
                ));
                return;
            }
            
            // Validate account exists in Registration_Request__c
            if (!validateEmployerAccount(accountId)) {
                res.statusCode = 403;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('Unauthorized: Account not registered')
                ));
                return;
            }
            
             // ✅ NEW: Debug path parsing
                String requestPath = req.requestURI;
                System.debug('Full Request URI: ' + requestPath);
            
            // Parse URL path to get candidate ID or resource type
                String[] pathParts = req.requestURI.split('/');
                String candidateIdOrResource = null;
            
            // Check if ID/resource is provided in URL (at index 5)
                if (pathParts.size() > 3 && String.isNotBlank(pathParts[3])) {
                    candidateIdOrResource = pathParts[3];
                    System.debug('Parsed candidateIdOrResource: ' + candidateIdOrResource);
                }
            
            if (String.isNotBlank(candidateIdOrResource) && candidateIdOrResource.toLowerCase() == 'campaigns') {
                	getActiveCampaigns(accountId, res);
                } else if (String.isNotBlank(candidateIdOrResource)) {
                    // Get single candidate detail (existing logic unchanged)
                    getCandidateDetail(candidateIdOrResource, accountId, res);
                } else {
                    // Get candidates list (existing logic unchanged)
                    getCandidatesList(accountId, req, res);
                }
                
           	 } catch (Exception e) {
                handleException(e);
            }
    }
    
    /**
     * Helper: Get candidates list
     */
    private static void getCandidatesList(Id accountId, RestRequest req, RestResponse res) {
        
        // Get query parameters with defensive null checks
        String talentPoolId = req.params.get('talentPoolId');
        String searchTerm = req.params.get('search');
        String sortByParam = req.params.get('sortBy');
        String sortBy = String.isBlank(sortByParam) ? 'matchScore' : sortByParam;
        String sortOrderParam = req.params.get('sortOrder');
        String sortOrder = String.isBlank(sortOrderParam) ? 'desc' : sortOrderParam;
        
        String pageNumberParam = req.params.get('pageNumber');
        Integer pageNumber = String.isBlank(pageNumberParam) ? 0 : Integer.valueOf(pageNumberParam);
        String pageSizeParam = req.params.get('pageSize');
        Integer pageSize = String.isBlank(pageSizeParam) ? 10 : Integer.valueOf(pageSizeParam);
        
        String statusFilter = req.params.get('status');
        
        System.debug('=== getCandidatesList START ===');
        System.debug('AccountId: ' + accountId);
        System.debug('Params → talentPoolId=' + talentPoolId +
            ', search=' + searchTerm +
            ', sortBy=' + sortBy +
            ', sortOrder=' + sortOrder +
            ', pageNumber=' + pageNumber +
            ', pageSize=' + pageSize +
            ', status=' + statusFilter);
        
        // Validate pagination
        if (pageSize > 100) pageSize = 100;
        if (pageSize < 1) pageSize = 10;
        if (pageNumber < 0) pageNumber = 0;
        
        Integer offset = pageNumber * pageSize;
        
        // Build base query
        String baseQuery = 'SELECT Id, ContactId, Contact.Id, Contact.Name, Contact.R_ATS__Skills__c, ' +
            'Contact.Years_Experience__c, Contact.MailingCity, Contact.MailingState, Contact.MailingCountry, ' +
            'Contact.Anonymized_Name__c, Contact.Job_Role__c, Contact.Status__c, ' +
            'Contact.Interest_Notes__c, Contact.Short_Term_Goals__c, Contact.Long_Term_Goals__c, ' +
            'Contact.Expected_Salary__c, Contact.Work_Preference__c, Contact.Candidate_Sentiment__c, ' +
            'Contact.Availability__c, Contact.Skill_Ratings__c, AI_Match_Score__c, CampaignId ' +
            'FROM CampaignMember WHERE Campaign.Employer__c = :accountId AND Status != \'Expired\'';
        
        // Add talent pool filter
        if (String.isNotBlank(talentPoolId)) {
            baseQuery += ' AND CampaignId = :talentPoolId';
        }
        
        // Add status filter
        if (String.isNotBlank(statusFilter)) {
            baseQuery += ' AND Contact.Candidate_Status__c = :statusFilter';
        }
        
        // Add search filter
        if (String.isNotBlank(searchTerm)) {
            String searchLike = '%' + searchTerm.toLowerCase() + '%';
            baseQuery += ' AND (Contact.Name LIKE :searchLike ' +
                'OR Contact.Anonymized_Name__c LIKE :searchLike)';
                
        }
        
        // Add sorting
        String sortField = getSortField(sortBy);
        String orderDirection = String.isBlank(sortOrder) || sortOrder.toLowerCase() == 'desc' ? 'DESC' : 'ASC';
        
        System.debug('Sort Field: ' + sortField);
        System.debug('Order Direction: ' + orderDirection);
        
        baseQuery += ' ORDER BY ' + sortField + ' ' + orderDirection;
        
        // Get total count
        String countQuery = 'SELECT COUNT() FROM CampaignMember WHERE Campaign.Employer__c = :accountId AND Status != \'Expired\'';
        if (String.isNotBlank(talentPoolId)) {
            countQuery += ' AND CampaignId = :talentPoolId';
        }
        if (String.isNotBlank(statusFilter)) {
            countQuery += ' AND Contact.Candidate_Status__c = :statusFilter';
        }
        if (String.isNotBlank(searchTerm)) {
            String searchLike = '%' + searchTerm.toLowerCase() + '%';
            countQuery += ' AND (Contact.Name LIKE :searchLike OR Contact.Anonymized_Name__c LIKE :searchLike)';
        }
        
        Integer totalCount = Database.countQuery(countQuery);
        System.debug('Total count: ' + totalCount);
        
        // Add pagination
        baseQuery += ' LIMIT :pageSize OFFSET :offset';
        System.debug('Final SOQL Query: ' + baseQuery);
        
        try {
            // Execute query
            List<CampaignMember> campaignMembers = Database.query(baseQuery);
            System.debug('Records returned: ' + campaignMembers.size());
            
            // Transform to DTOs
            List<CandidateDTO> candidates = new List<CandidateDTO>();
            for (CampaignMember member : campaignMembers) {
                candidates.add(transformToDTO(member));
            }
            System.debug('DTO list size: ' + candidates.size());
            
            // Build response
            CandidateListResponse response = new CandidateListResponse(
                candidates,
                totalCount,
                pageNumber,
                pageSize,
                'success'
            );
            
            RestContext.response.statusCode = 200;
            RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Query error: ' + e.getMessage());
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('Error retrieving candidates: ' + e.getMessage())
            ));
        }
    }
    
    /**
     * Helper: Get single candidate detail
     */
    private static void getCandidateDetail(String candidateId, Id accountId, RestResponse res) {
        System.debug('=== getCandidateDetail START ===');
        System.debug('Requested candidateId: ' + candidateId);
        System.debug('AccountId: ' + accountId);
        
        if (String.isBlank(candidateId)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('Missing candidate ID')
            ));
            return;
        }
        
        try {
            CampaignMember member = [
                SELECT Id, ContactId, Contact.Id, Contact.Name, Contact.R_ATS__Skills__c,
                    Contact.Years_Experience__c, Contact.MailingCity, Contact.MailingState, Contact.MailingCountry,
                    Contact.Anonymized_Name__c, Contact.Job_Role__c, Contact.Status__c,
                    Contact.Interest_Notes__c, Contact.Short_Term_Goals__c, Contact.Long_Term_Goals__c,
                    Contact.Expected_Salary__c, Contact.Work_Preference__c, Contact.Candidate_Sentiment__c,
                    Contact.Availability__c, Contact.Skill_Ratings__c, AI_Match_Score__c
                FROM CampaignMember
                WHERE Id = :candidateId AND Campaign.Employer__c = :accountId
                LIMIT 1
            ];
            
            System.debug('Candidate found: ' + member.Id);
            
            CandidateDTO candidate = transformToDTO(member);
            
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(candidate));
        } catch (QueryException qe) {
            System.debug('Candidate not found: ' + qe.getMessage());
            res.statusCode = 404;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('Candidate not found')
            ));
        }
    }
    
    /**
     * POST /api/candidates/bulk-action, /api/candidates/export, or /api/candidates/interview-request
     * Handle bulk actions, export, or interview requests
     */
    @HttpPost
    global static void doPost() {
        try {
            System.debug('=== CandidateAPI.doPost START ===');
            System.debug('Request URI: ' + RestContext.request.requestURI);
            System.debug('Raw body: ' + RestContext.request.requestBody);
            
            RestRequest req = RestContext.request;
            RestResponse res = RestContext.response;
            
            // Parse request body to get accountId
            String requestBody = req.requestBody.toString();
            Map<String, Object> requestMap = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
            
            String accountIdParam = (String) requestMap.get('accountId');
            
            if (String.isBlank(accountIdParam)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('accountId is required in request body')
                ));
                return;
            }
            
            Id accountId;
            try {
                accountId = Id.valueOf(accountIdParam);
            } catch (Exception e) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('Invalid accountId format')
                ));
                return;
            }
            
            // Validate account exists
            if (!validateEmployerAccount(accountId)) {
                res.statusCode = 403;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('Unauthorized: Account not registered')
                ));
                return;
            }
            
            // Determine action type from URL path
            String[] pathParts = req.requestURI.split('/');
            String action = null;
            
            System.debug('Path Parts: ' + String.join(pathParts, ' | '));
            System.debug('Path Parts Size: ' + pathParts.size());
            
            // Action is at index 3: /api/candidates/export or /api/candidates/bulk-action
            if (pathParts.size() > 3 && String.isNotBlank(pathParts[3])) {
                action = pathParts[3].toLowerCase();
                System.debug('Parsed action: ' + action);
            }
            
            if (action == 'bulk-action') {
                performBulkAction(accountId, requestMap, res);
            } else if (action == 'export') {
                exportCandidates(accountId, requestMap, res);
            } else if (action == 'interview-request') {
                requestInterview(accountId, requestMap, res);
            } else if (action == 'send-email') {
                sendEmailToCandidate(accountId, requestMap, res);
            } else if (action == 'add-to-campaign') {
                addToCampaign(accountId, requestMap, res);
            } else if (action == 'add-to-existing-campaign') {  // ⭐ ADD THIS LINE
                addToExistingCampaign(accountId, requestMap, res);  // ⭐ ADD THIS LINE
            }else {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('Invalid action. Use /bulk-action, /export, or /interview-request')
                ));
            }
            
        } catch (Exception e) {
            handleException(e);
        }
    }
    
    /**
     * Helper: Perform bulk action on candidates
     */
    private static void performBulkAction(Id accountId, Map<String, Object> requestMap, RestResponse res) {
        System.debug('=== performBulkAction START ===');
        System.debug('AccountId: ' + accountId);
        System.debug('Request: ' + JSON.serialize(requestMap));
        
        try {
            // Parse bulk action request
            BulkActionRequest actionReq = (BulkActionRequest) JSON.deserialize(
                JSON.serialize(requestMap),
                BulkActionRequest.class
            );
            
            if (actionReq == null || actionReq.candidateIds == null || actionReq.candidateIds.isEmpty()) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('Missing candidateIds or action')
                ));
                return;
            }
            
            // Get campaign members
            List<CampaignMember> members = [
                SELECT Id, ContactId, Contact.Id, Contact.Status__c
                FROM CampaignMember
                WHERE Id IN :actionReq.candidateIds AND Campaign.Employer__c = :accountId
            ];
            
            if (members.isEmpty()) {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('No candidates found')
                ));
                return;
            }
            
            // Process action
            if (actionReq.action == 'updateStatus' && String.isNotBlank(actionReq.status)) {
                List<Contact> contacts = new List<Contact>();
                for (CampaignMember member : members) {
                    Contact c = member.Contact;
                    c.Status__c = actionReq.status;
                    contacts.add(c);
                }
                update contacts;
                System.debug('Updated ' + contacts.size() + ' contacts');
            } else if (actionReq.action == 'delete') {
                delete members;
                System.debug('Deleted ' + members.size() + ' members');
            } else {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('Invalid action: ' + actionReq.action)
                ));
                return;
            }
            
            BulkActionResponse response = new BulkActionResponse(
                actionReq.candidateIds.size(),
                actionReq.action + ' completed successfully',
                'success'
            );
            
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(response));
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'performBulkAction error: ' + e.getMessage());
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('Error processing bulk action: ' + e.getMessage())
            ));
        }
    }
    
    /**
     * Helper: Export candidates to CSV
     */
    private static void exportCandidates(Id accountId, Map<String, Object> requestMap, RestResponse res) {
        try {
            System.debug('=== exportCandidates START ===');
            System.debug('AccountId: ' + accountId);
            
            List<CampaignMember> members = [
                SELECT Id, ContactId, Contact.Id, Contact.Name, Contact.R_ATS__Skills__c,
                    Contact.Years_Experience__c, Contact.MailingCity, Contact.MailingState, Contact.MailingCountry,
                    Contact.Anonymized_Name__c, Contact.Job_Role__c, Contact.Status__c,
                    Contact.Interest_Notes__c, Contact.Expected_Salary__c, Contact.Work_Preference__c,
                    Contact.Candidate_Sentiment__c, AI_Match_Score__c
                FROM CampaignMember
                WHERE Campaign.Employer__c = :accountId AND Status = 'Interested'
                LIMIT 50000
            ];
            
            System.debug('Records to export: ' + members.size());
            
            String csv = generateCSV(members);
            
            res.statusCode = 200;
            res.addHeader('Content-Type', 'text/csv');
            res.addHeader('Content-Disposition', 'attachment; filename="candidates.csv"');
            res.responseBody = Blob.valueOf(csv);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'exportCandidates error: ' + e.getMessage());
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('Error exporting candidates: ' + e.getMessage())
            ));
        }
    }
    
    /**
     * Helper: Request interview for candidates
     * Creates Task record for interview scheduling
     */
    private static void requestInterview(Id accountId, Map<String, Object> requestMap, RestResponse res) {
        System.debug('=== requestInterview (BULKIFIED) START ===');
        System.debug('AccountId: ' + accountId);
        System.debug('Request: ' + JSON.serialize(requestMap));
        
        try {
            // Parse interview request
            InterviewRequest interviewReq = (InterviewRequest) JSON.deserialize(
                JSON.serialize(requestMap),
                InterviewRequest.class
            );
            
            System.debug('Interview Request: ' + JSON.serialize(interviewReq));
            
            // Validate required fields
            if (interviewReq.candidateIds == null || interviewReq.candidateIds.isEmpty()) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('candidateIds list is required')
                ));
                return;
            }
            
            if (String.isBlank(interviewReq.interviewFormat)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('interviewFormat is required')
                ));
                return;
            }
            
            if (String.isBlank(interviewReq.position)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('position is required')
                ));
                return;
            }
            
            System.debug('Processing ' + interviewReq.candidateIds.size() + ' candidates');
            
            // ✅ BULK QUERY: Get ALL candidates in one query
            List<CampaignMember> campaignMembers = [
                SELECT Id, ContactId, Contact.Id, Contact.Name, Contact.Email
                FROM CampaignMember
                WHERE Id IN :interviewReq.candidateIds 
                AND Campaign.Employer__c = :accountId
            ];
            
            System.debug('Found ' + campaignMembers.size() + ' campaign members');
            
            if (campaignMembers.isEmpty()) {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('No candidates found for the provided IDs')
                ));
                return;
            }
            
            // ✅ BULK CREATE: Build all Task records
            Account employerAccount = [
                SELECT Name
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];

            List<Task> interviewTasks = new List<Task>();
            
            for (CampaignMember campaignMember : campaignMembers) {
                Task interviewTask = new Task();
                interviewTask.WhoId = campaignMember.Contact.Id;
                interviewTask.WhatId = accountId;
                interviewTask.Subject = 'Interview - ' + interviewReq.position;
                interviewTask.ActivityDate = Date.today().addDays(3); // Default to 3 days from now
                interviewTask.Status = 'Open';
                interviewTask.Priority = 'High';
                interviewTask.Type = 'Call';
                
                // Build description with interview details
                String description = 'Interview Request Details\n';
                description += '================================\n';
                description += 'Position: ' + interviewReq.position + '\n';
                description += 'Interview Format: ' + interviewReq.interviewFormat + '\n';
                
                if (String.isNotBlank(interviewReq.interviewRound)) {
                    description += 'Interview Round: ' + interviewReq.interviewRound + '\n';
                }
                
                if (String.isNotBlank(interviewReq.duration)) {
                    description += 'Expected Duration: ' + interviewReq.duration + '\n';
                }
                
                description += '\nCandidate: ' + campaignMember.Contact.Name + '\n';
                description += 'Email: ' + (campaignMember.Contact.Email ?? 'N/A') + '\n';
                description += '\nPlease contact the candidate to schedule the interview.';
                
                if (String.isNotBlank(interviewReq.message)) {
                    description += '\n\nAdditional Notes:\n' + interviewReq.message;
                }
                
                interviewTask.Description = description;
                interviewTasks.add(interviewTask);
            }
            
            System.debug('Created ' + interviewTasks.size() + ' task records');
            
            // ✅ BULK INSERT with partial success allowed
            Database.SaveResult[] saveResults = Database.insert(interviewTasks, false);
            
            System.debug('Insert results received: ' + saveResults.size());
            
            // Process results
            List<InterviewTaskResult> taskResults = new List<InterviewTaskResult>();
            List<NotificationService.NotificationRequest> notificationRequests = new List<NotificationService.NotificationRequest>();
            Integer successCount = 0;
            Integer failureCount = 0;
            
            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                CampaignMember member = campaignMembers[i];
                
                InterviewTaskResult result = new InterviewTaskResult();
                result.candidateId = member.Id;
                result.candidateName = member.Contact.Name;
                result.success = sr.isSuccess();
                
                if (sr.isSuccess()) {
                    result.taskId = sr.getId();
                    result.message = 'Interview task created successfully';
                    successCount++;

                    NotificationService.NotificationRequest notificationRequest =
                        new NotificationService.NotificationRequest();
                    notificationRequest.recipientId = member.ContactId;
                    notificationRequest.notificationType = 'Interview';
                    notificationRequest.title = 'Interview invitation from ' + employerAccount.Name;
                    notificationRequest.description = 'You have been invited to interview for ' +
                        interviewReq.position + '. Review and confirm.';
                    notificationRequest.linkTo = '/dashboard';
                    notificationRequest.priority = 'Urgent';
                    notificationRequests.add(notificationRequest);
                    System.debug('✓ Task created for candidate: ' + member.Contact.Name);
                } else {
                    result.taskId = null;
                    result.message = sr.getErrors()[0].getMessage();
                    failureCount++;
                    System.debug('✗ Failed for candidate: ' + member.Contact.Name + 
                        ' | Error: ' + result.message);
                }
                
                taskResults.add(result);
            }
            
            NotificationService.notifyMany(notificationRequests);

            System.debug('Success: ' + successCount + ', Failures: ' + failureCount);
            
            // Build response
            BulkInterviewResponse response = new BulkInterviewResponse();
            response.totalRequested = campaignMembers.size();
            response.successCount = successCount;
            response.failureCount = failureCount;
            response.taskResults = taskResults;
            response.status = failureCount == 0 ? 'success' : 'partial_success';
            response.message = successCount + ' interview requests created, ' + 
                              failureCount + ' failed';
            
            res.statusCode = failureCount == 0 ? 200 : 207;
            res.responseBody = Blob.valueOf(JSON.serialize(response));
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'requestInterview error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('Error creating interview requests: ' + e.getMessage())
            ));
        }
    }
    
     /**
     * Helper: Send email to candidate with Salesforce logging
     * Creates Task + ActivityHistory for communication tracking
     */

    private static void sendEmailToCandidate(Id accountId, Map<String, Object> requestMap, RestResponse res) {
        System.debug('=== sendEmailToCandidate START ===');
        System.debug('AccountId: ' + accountId);
        System.debug('Request: ' + JSON.serialize(requestMap));
        
        try {
            // Parse email request
            EmailRequest emailReq = (EmailRequest) JSON.deserialize(
                JSON.serialize(requestMap),
                EmailRequest.class
            );
            
            System.debug('Email Request: ' + JSON.serialize(emailReq));
            
            // ✅ Validate required fields
            if (String.isBlank(emailReq.to)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('Recipient email (to) is required')
                ));
                return;
            }
            
            if (String.isBlank(emailReq.subject)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('Email subject is required')
                ));
                return;
            }
            
            if (String.isBlank(emailReq.body)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('Email body is required')
                ));
                return;
            }
            
            if (String.isBlank(emailReq.candidateId)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('Candidate ID is required')
                ));
                return;
            }
            
            // ✅ Validate email addresses
            validateEmailAddresses(emailReq.to, emailReq.cc, emailReq.bcc);
            
            // ✅ Get candidate and account information
            CampaignMember candidate = [
                SELECT Id, ContactId, Contact.Id, Contact.Name, Contact.Email
                FROM CampaignMember
                WHERE Id = :emailReq.candidateId AND Campaign.Employer__c = :accountId
                LIMIT 1
            ];
            
            System.debug('Candidate found: ' + candidate.Contact.Name);
            
            // ✅ Get account/employer details
            Account employer = [
                SELECT Id, Name, BillingCity, BillingState, BillingCountry
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];
            
            System.debug('Employer found: ' + employer.Name);
            
            // ✅ NEW: Process base64-encoded attachments
            List<Messaging.EmailFileAttachment> emailAttachments = new List<Messaging.EmailFileAttachment>();
            
            if (emailReq.attachments != null && !emailReq.attachments.isEmpty()) {
                System.debug('Processing ' + emailReq.attachments.size() + ' base64-encoded attachments');
                
                for (AttachmentData attData : emailReq.attachments) {
                    try {
                        // Validate attachment data
                        if (String.isBlank(attData.filename) || String.isBlank(attData.content)) {
                            System.debug('⚠ Skipping attachment: missing filename or content');
                            continue;
                        }
                        
                        String base64Content = attData.content;
                        if (base64Content.contains(',')) {
                            base64Content = base64Content.substringAfter(',');
                            System.debug('Stripped Data URL prefix from: ' + attData.filename);
                        }
                        
                        // Decode base64 content to Blob
                        Blob decodedContent = EncodingUtil.base64Decode(attData.content);
                        
                        System.debug('Decoded attachment: ' + attData.filename + 
                                    ' | Size: ' + decodedContent.size() + ' bytes');
                        
                        // Validate file size (max 25MB per attachment)
                        if (decodedContent.size() > 26214400) { // 25MB in bytes
                            System.debug('⚠ Attachment too large: ' + attData.filename + 
                                        ' (' + decodedContent.size() + ' bytes)');
                            continue;
                        }
                        
                        // Create EmailFileAttachment
                        Messaging.EmailFileAttachment emailAtt = new Messaging.EmailFileAttachment();
                        emailAtt.setFileName(attData.filename);
                        emailAtt.setBody(decodedContent);
                        emailAtt.setContentType(String.isNotBlank(attData.contentType) 
                            ? attData.contentType 
                            : 'application/octet-stream');
                        
                        emailAttachments.add(emailAtt);
                        System.debug('✓ Attachment ready: ' + attData.filename);
                        
                        // Salesforce limit: max 5 attachments per email
                        if (emailAttachments.size() >= 5) {
                            System.debug('⚠ Max 5 attachments reached, skipping remaining');
                            break;
                        }
                        
                    } catch (Exception e) {
                        System.debug( 
                            'Failed to process attachment ' + attData.filename + 
                            ': ' + e.getMessage());
                        // Continue with other attachments if one fails
                    }
                }
                
                System.debug('Successfully prepared ' + emailAttachments.size() + ' attachments');
            }
            
            // ✅ Create email message
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            
            // Set from address - use employer email or org-wide address
            String fromAddress = getOrgWideEmailAddress(employer);
            if (String.isBlank(fromAddress)) {
                fromAddress = UserInfo.getUserEmail();
            }
            mail.setOrgWideEmailAddressId(getOrgWideEmailAddressId(employer));
            
            // Set recipients
            mail.setToAddresses(new String[] { emailReq.to });
            
            if (String.isNotBlank(emailReq.cc)) {
                mail.setCcAddresses(parseCcAddresses(emailReq.cc));
            }
            
            if (String.isNotBlank(emailReq.bcc)) {
                mail.setBccAddresses(parseCcAddresses(emailReq.bcc));
            }
            
            mail.setSubject(emailReq.subject);
            mail.setPlainTextBody(emailReq.body);
            
            // Link email to contact record for activity tracking
            mail.setTargetObjectId(candidate.Contact.Id);
            
            // Set no-reply options
            mail.setSaveAsActivity(true);
            
            // ✅ Attach files if any
            if (!emailAttachments.isEmpty()) {
                mail.setFileAttachments(emailAttachments);
                System.debug('✓ ' + emailAttachments.size() + ' attachments set on email');
            }
            
            System.debug('Email message created successfully');
            
            // ✅ BULK SEND - Send email(s)
            Messaging.SendEmailResult[] results = Messaging.sendEmail(
                new Messaging.SingleEmailMessage[] { mail },
                false  // allowPartialSend
            );
            
            System.debug('Email send results received: ' + results.size());
            
            // ✅ Check send result
            Messaging.SendEmailResult sendResult = results[0];
            
            if (!sendResult.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Email send failed');
                for (Messaging.SendEmailError error : sendResult.getErrors()) {
                    System.debug('Error: ' + error.getMessage());
                }
                
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('Failed to send email: ' + sendResult.getErrors()[0].getMessage())
                ));
                return;
            }
            
            System.debug('✓ Email sent successfully');
            
            // ✅ Create Activity/Task for communication history logging
            Task emailTask = new Task();
            emailTask.WhoId = candidate.Contact.Id;
            emailTask.WhatId = accountId;
            emailTask.Subject = 'Email: ' + emailReq.subject;
            emailTask.ActivityDate = Date.today();
            emailTask.Status = 'Completed';
            emailTask.Type = 'Email';
            emailTask.Priority = 'Normal';
            emailTask.ReminderDateTime = DateTime.now();
            
            String taskDescription = 'Email Sent\n';
            taskDescription += '=====================================\n';
            taskDescription += 'To: ' + emailReq.to + '\n';
            
            if (String.isNotBlank(emailReq.cc)) {
                taskDescription += 'CC: ' + emailReq.cc + '\n';
            }
            if (String.isNotBlank(emailReq.bcc)) {
                taskDescription += 'BCC: ' + emailReq.bcc + '\n';
            }
            
            taskDescription += 'Subject: ' + emailReq.subject + '\n';
            taskDescription += 'Sent By: ' + UserInfo.getName() + '\n';
            taskDescription += 'Sent At: ' + DateTime.now().format() + '\n';
            taskDescription += 'Status: Delivered\n';
            
            // ✅ Document attachments in task
            if (!emailAttachments.isEmpty()) {
                taskDescription += 'Attachments: ' + emailAttachments.size() + '\n';
                for (Messaging.EmailFileAttachment att : emailAttachments) {
                    taskDescription += '  - ' + att.getFileName() + '\n';
                }
            }
            
            taskDescription += '=====================================\n\n';
            taskDescription += 'Message Body:\n' + emailReq.body;
            
            emailTask.Description = taskDescription;
            
            insert emailTask;
            System.debug('Activity/Task created: ' + emailTask.Id);
            
            // ✅ Build success response
            EmailResponse emailResponse = new EmailResponse();
            emailResponse.success = true;
            emailResponse.message = 'Email sent successfully to ' + emailReq.to;
            emailResponse.taskId = emailTask.Id;
            emailResponse.timestamp = DateTime.now().format();
            emailResponse.sender = fromAddress;
            emailResponse.recipient = emailReq.to;
            emailResponse.candidateId = candidate.Id;
            emailResponse.status = 'delivered';
            emailResponse.attachmentCount = emailAttachments.size();
            
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(emailResponse));
            
            System.debug('=== sendEmailToCandidate COMPLETED SUCCESSFULLY ===');
            
        } catch (QueryException qe) {
            System.debug(LoggingLevel.ERROR, 'Candidate not found: ' + qe.getMessage());
            res.statusCode = 404;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('Candidate not found for the provided ID')
            ));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'sendEmailToCandidate error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('Error sending email: ' + e.getMessage())
            ));
        }
    }
    
    /**
     * Helper: Validate email addresses format
     */
    private static void validateEmailAddresses(String toEmail, String ccEmails, String bccEmails) {
        String emailPattern = '^[a-zA-Z0-9._%-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,4}$';
        Pattern p = Pattern.compile(emailPattern);
        
        // Validate TO
        if (!p.matcher(toEmail.trim()).matches()) {
            throw new IllegalArgumentException('Invalid recipient email address: ' + toEmail);
        }
        
        // Validate CC
        if (String.isNotBlank(ccEmails)) {
            List<String> ccList = parseCcAddresses(ccEmails);
            for (String cc : ccList) {
                if (!p.matcher(cc).matches()) {
                    throw new IllegalArgumentException('Invalid CC email address: ' + cc);
                }
            }
        }
        
        // Validate BCC
        if (String.isNotBlank(bccEmails)) {
            List<String> bccList = parseCcAddresses(bccEmails);
            for (String bcc : bccList) {
                if (!p.matcher(bcc).matches()) {
                    throw new IllegalArgumentException('Invalid BCC email address: ' + bcc);
                }
            }
        }
    }
    
    /**
     * Helper: Parse comma-separated email addresses
     */
    private static List<String> parseCcAddresses(String emails) {
        List<String> emailList = new List<String>();
        if (String.isBlank(emails)) return emailList;
        
        for (String email : emails.split(',')) {
            String trimmed = email.trim();
            if (String.isNotBlank(trimmed)) {
                emailList.add(trimmed);
            }
        }
        return emailList;
    }
    
    /**
     * Helper: Get Org-Wide Email Address ID
     * This allows sending from a system email instead of user email
     */
    private static Id getOrgWideEmailAddressId(Account employer) {
        try {
            // Try to find org-wide email matching employer name
            OrgWideEmailAddress[] owea = [
                SELECT Id, DisplayName, Address
                FROM OrgWideEmailAddress
                WHERE DisplayName LIKE :('%' + employer.Name + '%')
                LIMIT 1
            ];
            
            if (owea.size() > 0) {
                System.debug('Found OrgWideEmailAddress: ' + owea[0].Address);
                return owea[0].Id;
            }
            
            // Fallback: Get any available org-wide email
            OrgWideEmailAddress[] fallback = [
                SELECT Id, DisplayName, Address
                FROM OrgWideEmailAddress
                LIMIT 1
            ];
            
            if (fallback.size() > 0) {
                System.debug('Using fallback OrgWideEmailAddress: ' + fallback[0].Address);
                return fallback[0].Id;
            }
            
        } catch (Exception e) {
            System.debug('No OrgWideEmailAddress found: ' + e.getMessage());
        }
        
        return null;
    }
    
    /**
     * Helper: Get email address from Org-Wide Email
     */
    private static String getOrgWideEmailAddress(Account employer) {
        try {
            OrgWideEmailAddress[] owea = [
                SELECT Address
                FROM OrgWideEmailAddress
                WHERE DisplayName LIKE :('%' + employer.Name + '%')
                LIMIT 1
            ];
            
            if (owea.size() > 0) {
                return owea[0].Address;
            }
        } catch (Exception e) {
            System.debug('Error getting org-wide email: ' + e.getMessage());
        }
        
        return null;
    }
    
     /**
     * Helper: Add candidates to campaign
     * Creates or uses existing campaign and adds candidates as Campaign Members
     * Tracks candidates in hiring pipeline
     */
    
    
    private static void addToCampaign(Id accountId, Map<String, Object> requestMap, RestResponse res) {
        
        System.debug('=== addToCampaign START ===');
        System.debug('AccountId: ' + accountId);
        System.debug('Request: ' + JSON.serialize(requestMap));
    
    try {
        // Parse request
        AddToCampaignRequest campaignReq = (AddToCampaignRequest) JSON.deserialize(
            JSON.serialize(requestMap),
            AddToCampaignRequest.class
        );
        
        System.debug('Campaign Request: ' + JSON.serialize(campaignReq));
        
        // ✅ Validate required fields
        if (campaignReq.candidateIds == null || campaignReq.candidateIds.isEmpty()) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('candidateIds list is required')
            ));
            return;
        }
        
        // ✅ FIX #1: Validate Campaign Member Status against allowed values
       // Set<String> validStatuses = new Set<String>{
         //   'Interested', 'Applied', 'Contacted', 'Under Review', 'Shortlisted', 'Rejected'
        //};
        
        //if (String.isBlank(campaignReq.status) || !validStatuses.contains(campaignReq.status)) {
        //   res.statusCode = 400;
        //    res.responseBody = Blob.valueOf(JSON.serialize(
        //        new ErrorResponse('Invalid Campaign Member status. Must be one of: Interested, Applied, Contacted, Under Review, Shortlisted, Rejected')
        //    ));
        //    return;
        //}
        
        // ✅ Validate campaign selection - must provide either campaignId or campaignName
        if (String.isBlank(campaignReq.campaignId) && String.isBlank(campaignReq.campaignName)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('Either campaignId (existing) or campaignName (new) is required')
            ));
            return;
        }
        
        // ✅ FIX #2: Make position/job role REQUIRED for new campaigns
        if (String.isBlank(campaignReq.campaignId) && String.isBlank(campaignReq.position)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('Campaign position/job role is required when creating a new campaign')
            ));
            return;
        }
        
        System.debug('Processing ' + campaignReq.candidateIds.size() + ' candidates');
        
        // ✅ Query Contact details using provided Contact IDs
        Map<Id, String> contactNameMap = new Map<Id, String>();
        Map<Id, String> contactEmailMap = new Map<Id, String>();
        
        List<CampaignMember> talentPoolMembers = [
            SELECT Id, Name, ContactId, Contact.Id, Contact.Name, Contact.Email, Contact.R_ATS__Skills__c
            FROM CampaignMember
            WHERE Id IN :campaignReq.candidateIds  // CHANGED: Using campaignIds directly
            AND Campaign.Employer__c = :accountId  // CHANGED: Cross-object filter added
        ];
        
        System.debug('Found ' + talentPoolMembers.size() + ' contacts');
        
        if (talentPoolMembers.isEmpty()) {
            res.statusCode = 404;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('No contacts found for the provided IDs')
            ));
            return;
        }
        
        // ✅ Build name and email maps
        Set<Id> contactIds = new Set<Id>();
        
        for (CampaignMember member : talentPoolMembers) {
            contactIds.add(member.ContactId);
            contactNameMap.put(member.ContactId, member.Contact.Name);
            contactEmailMap.put(member.ContactId, member.Contact.Email);
        }
        
        // ✅ Determine campaign - use existing or create new
        Id campaignId;
        String campaignName;
        
        if (String.isNotBlank(campaignReq.campaignId)) {
            // ✅ Use existing campaign
            campaignId = campaignReq.campaignId;
            
            Campaign existingCampaign = [
                SELECT Id, Name
                FROM Campaign
                WHERE Id = :campaignId
                LIMIT 1
            ];
            
            campaignName = existingCampaign.Name;
            System.debug('Using existing campaign: ' + campaignName + ' (' + campaignId + ')');
            
        } else {
            // ✅ Create new campaign
            Id jobRecordTypeId = Schema.SObjectType.Campaign.getRecordTypeInfosByDeveloperName()
                .get('Talent_Pool').getRecordTypeId();
            
            Campaign newCampaign = new Campaign();
            newCampaign.Name = campaignReq.campaignName;
            newCampaign.RecordTypeId = jobRecordTypeId;
            newCampaign.Employer__c = accountId;
            newCampaign.Status = 'Active';
            newCampaign.isActive = true;
            newCampaign.StartDate = Date.today();
            newCampaign.Description = 'Job Position: ' + campaignReq.position;
            
            insert newCampaign;
            campaignId = newCampaign.Id;
            campaignName = newCampaign.Name;
            
            System.debug('✓ New campaign created: ' + campaignName + ' (' + campaignId + ')');
            TalentPoolService.createTalentPoolStatuses(new List<Id> { campaignId });
			System.debug('✓ Campaign Member Statuses created for campaign: ' + campaignName);
        }
        
        // ✅ Check for existing Campaign Members in target campaign
        Set<Id> existingContactIds = new Set<Id>();
        List<CampaignMember> existingMembers = [
            SELECT Id, ContactId
            FROM CampaignMember
            WHERE CampaignId = :campaignId AND ContactId IN :contactIds
        ];
        
        for (CampaignMember existing : existingMembers) {
            existingContactIds.add(existing.ContactId);
            System.debug('⚠ Contact already in campaign: ' + contactNameMap.get(existing.ContactId));
        }
        
        // ✅ Build list of NEW Campaign Members to create
        List<CampaignMember> newCampaignMembers = new List<CampaignMember>();
        
        for (Id contactId : contactIds) {
            // Skip if already exists
            if (existingContactIds.contains(contactId)) {
                continue;
            }
            
            CampaignMember newMember = new CampaignMember();
            newMember.CampaignId = campaignId;
            newMember.ContactId = contactId;
            newMember.Status = campaignReq.status;
            
            newCampaignMembers.add(newMember);
        }
        
        System.debug('New campaign members to create: ' + newCampaignMembers.size());
        System.debug('Already existing: ' + existingContactIds.size());
        
        // ✅ BULK INSERT - Create all new Campaign Members
        List<AddToCampaignResult> campaignResults = new List<AddToCampaignResult>();
        Integer successCount = 0;
        Integer failureCount = 0;
        
        if (!newCampaignMembers.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(newCampaignMembers, false);
            
            System.debug('Insert results received: ' + saveResults.size());
            
            // Process results
            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                CampaignMember member = newCampaignMembers[i];
                Id contactId = member.ContactId;
                
                AddToCampaignResult result = new AddToCampaignResult();
                result.candidateId = member.Id;
                result.candidateName = contactNameMap.get(contactId);
                result.success = sr.isSuccess();
                
                if (sr.isSuccess()) {
                    result.campaignMemberId = sr.getId();
                    result.message = 'Added to campaign successfully';
                    successCount++;
                    System.debug('✓ Contact added to campaign: ' + result.candidateName);
                } else {
                    result.campaignMemberId = null;
                    result.message = sr.getErrors()[0].getMessage();
                    failureCount++;
                    System.debug('✗ Failed for contact: ' + result.candidateName + 
                        ' | Error: ' + result.message);
                }
                
                campaignResults.add(result);
            }
        } else {
            System.debug('ℹ No new members to add (all already in campaign)');
        }
        
        // ✅ Add already-existing members to results
        for (CampaignMember existing : existingMembers) {
            AddToCampaignResult result = new AddToCampaignResult();
            result.candidateId = existing.Id;
            result.candidateName = contactNameMap.get(existing.ContactId);
            result.success = true;
            result.campaignMemberId = existing.Id;
            result.message = 'Already member of this campaign';
            campaignResults.add(result);
        }
        
        System.debug('Success: ' + successCount + ', Failures: ' + failureCount + 
                    ', Already Existing: ' + existingContactIds.size());
        
        // ✅ Build response
        AddToCampaignResponse response = new AddToCampaignResponse();
        response.campaignId = campaignId;
        response.campaignName = campaignName;
        response.totalProcessed = talentPoolMembers.size();
        response.successCount = successCount;
        response.failureCount = failureCount;
        response.alreadyMemberCount = existingContactIds.size();
        response.campaignResults = campaignResults;
        response.status = failureCount == 0 ? 'success' : 'partial_success';
        response.message = successCount + ' candidates added, ' + 
                          existingContactIds.size() + ' already members, ' + 
                          failureCount + ' failed';
        
        res.statusCode = failureCount == 0 ? 200 : 207;
        res.responseBody = Blob.valueOf(JSON.serialize(response));
        
        System.debug('=== addToCampaign COMPLETED SUCCESSFULLY ===');
        
    } catch (QueryException qe) {
        System.debug(LoggingLevel.ERROR, 'Campaign or contact not found: ' + qe.getMessage());
        res.statusCode = 404;
        res.responseBody = Blob.valueOf(JSON.serialize(
            new ErrorResponse('Campaign or contact not found: ' + qe.getMessage())
        ));
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'addToCampaign error: ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
        
        res.statusCode = 400;
        res.responseBody = Blob.valueOf(JSON.serialize(
            new ErrorResponse('Error adding candidates to campaign: ' + e.getMessage())
        ));
    }
}

        
            
    /**
     * ⭐ NEW METHOD #1: Retrieve active campaigns for employer account
     * GET /api/candidates/campaigns?accountId=xxx
     * 
     * This is a NEW method - doesn't modify any existing code
     */
    private static void getActiveCampaigns(Id accountId, RestResponse res) {
        System.debug('=== getActiveCampaigns START ===');
        System.debug('AccountId: ' + accountId);
        
        try {
            // ✅ Query active campaigns for employer
            List<Campaign> activeCampaigns = [
                SELECT Id, Name, Status, StartDate, Description, RecordType.Name
                FROM Campaign
                WHERE Employer__c = :accountId 
                AND IsActive =true
                ORDER BY StartDate DESC, Name ASC
            ];
            
            System.debug('Active campaigns found: ' + activeCampaigns.size());
            
            // ✅ Transform to DTOs
            List<CampaignDTO> campaignDTOs = new List<CampaignDTO>();
            
            for (Campaign campaign : activeCampaigns) {
                // Get member count for each campaign
                Integer memberCount = [
                    SELECT COUNT()
                    FROM CampaignMember
                    WHERE CampaignId = :campaign.Id
                ];
                
                CampaignDTO dto = new CampaignDTO();
                dto.id = campaign.Id;
                dto.name = campaign.Name;
                dto.status = campaign.Status;
                dto.description = campaign.Description;
                dto.startDate = campaign.StartDate != null ? campaign.StartDate.format() : null;
                dto.recordTypeName = campaign.RecordType.Name;
                dto.memberCount = memberCount;
                
                campaignDTOs.add(dto);
            }
            
            System.debug('Campaign DTOs created: ' + campaignDTOs.size());
            
            // ✅ Build response
            CampaignListResponse response = new CampaignListResponse(
                campaignDTOs,
                campaignDTOs.size(),
                'success'
            );
            
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(response));
            
            System.debug('=== getActiveCampaigns COMPLETED SUCCESSFULLY ===');
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getActiveCampaigns error: ' + e.getMessage());
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('Error retrieving campaigns: ' + e.getMessage())
            ));
        }
    }
    
        
    /**
     * ⭐ NEW METHOD #2: Validate campaign selection and status
     * Used before adding candidates to existing campaign
     * 
     * This is a NEW method - doesn't modify any existing code
     */
    private static ValidationResult validateCampaignSelection(
        Id accountId, 
        String campaignId, 
        String status) {
        
        System.debug('=== validateCampaignSelection START ===');
        System.debug('CampaignId: ' + campaignId + ', Status: ' + status);
        
        ValidationResult result = new ValidationResult();
            
            /*
        
        // ✅ Check if campaignId is provided
        if (String.isBlank(campaignId)) {
            result.isValid = false;
            result.errorMessage = 'Campaign ID is required for existing campaign flow';
            return result;
        }
		*/
        
            /*
        // ✅ Check if status is provided
        if (String.isBlank(status)) {
            result.isValid = false;
            result.errorMessage = 'Campaign Member status is required';
            return result;
        }
            */
        
        // ✅ Validate status against allowed values
        /*
        Set<String> validStatuses = new Set<String>{
            'Interested', 'Applied', 'Contacted', 'Under Review', 'Shortlisted', 'Rejected'
        };
        
        if (!validStatuses.contains(status)) {
            result.isValid = false;
            result.errorMessage = 'Invalid Campaign Member status. Must be one of: ' + 
                                  String.join(new List<String>(validStatuses), ', ');
            return result;
        }
		*/
        
        try {
            // ✅ Verify campaign exists and belongs to employer
            Campaign campaign = [
                SELECT Id, Name, Status, Employer__c
                FROM Campaign
                WHERE Id = :campaignId
                LIMIT 1
            ];
            
            /*
            
            // ✅ Verify campaign belongs to correct employer
            if (campaign.Employer__c != accountId) {
                result.isValid = false;
                result.errorMessage = 'Campaign does not belong to your organization';
                result.campaignId = campaignId;
                return result;
            }
			*/
            
            // ✅ Check if campaign is active
            /*
            if (campaign.Status != 'Active') {
                result.isValid = false;
                result.errorMessage = 'Campaign must be active to add candidates. Current status: ' + campaign.Status;
                result.campaignId = campaignId;
                result.campaignName = campaign.Name;
                return result;
            }
			*/
            
            // ✅ Success: All validations passed
            result.isValid = true;
            result.campaignId = campaign.Id;
            result.campaignName = campaign.Name;
            result.status = campaign.Status;
            result.message = 'Campaign validation successful';
            
            System.debug('✓ Campaign validated: ' + campaign.Name);
            
        } catch (QueryException qe) {
            System.debug(LoggingLevel.WARN, 'Campaign not found: ' + campaignId);
            result.isValid = false;
            result.errorMessage = 'Campaign not found';
            result.campaignId = campaignId;
        }
        
        return result;
    }
    
        
    /**
     * ⭐ NEW METHOD #3: Add candidates to EXISTING selected campaign
     * POST /api/candidates/add-to-existing-campaign
     * 
     * This is a NEW method - doesn't modify any existing code
     */
    private static void addToExistingCampaign(Id accountId, Map<String, Object> requestMap, RestResponse res) {
        System.debug('=== addToExistingCampaign START ===');
        System.debug('AccountId: ' + accountId);
        System.debug('Request: ' + JSON.serialize(requestMap));
        
        try {
            // ✅ Parse request
            ExistingCampaignRequest campaignReq = (ExistingCampaignRequest) JSON.deserialize(
                JSON.serialize(requestMap),
                ExistingCampaignRequest.class
            );
            
            System.debug('Campaign Request: ' + JSON.serialize(campaignReq));
            System.debug('⭐ DEBUG: campaignReq.campaignId = ' + campaignReq.campaignId);
            System.debug('⭐ DEBUG: campaignReq.candidateIds = ' + campaignReq.candidateIds);
            System.debug('⭐ DEBUG: campaignReq.status = ' + campaignReq.status);
                
            // ✅ Step 1: Validate required fields
            /*
            if (campaignReq.candidateIds == null || campaignReq.candidateIds.isEmpty()) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('candidateIds list is required')
                ));
                return;
            }
			*/
            
            // ✅ Step 2: Validate campaign selection and status
            ValidationResult validationResult = validateCampaignSelection(
                accountId,
                campaignReq.campaignId,
                campaignReq.status
            );
            
            /*
            if (!validationResult.isValid) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse(validationResult.errorMessage)
                ));
                return;
            }
			*/
            
            System.debug('✓ Validation passed for campaign: ' + validationResult.campaignName);
            
            // ✅ Step 3: Get campaign details
            Id campaignId = validationResult.campaignId;
            String campaignName = validationResult.campaignName;
            
            System.debug('Processing ' + campaignReq.candidateIds.size() + ' candidates for campaign: ' + campaignName);
            
            // ✅ Step 4: Query candidate/contact details
            Map<Id, String> contactNameMap = new Map<Id, String>();
            Map<Id, String> contactEmailMap = new Map<Id, String>();
            
            List<CampaignMember> talentPoolMembers = [
                SELECT Id, ContactId, Contact.Id, Contact.Name, Contact.Email
                FROM CampaignMember
                WHERE Id IN :campaignReq.candidateIds
                AND Campaign.Employer__c = :accountId
            ];
            
            System.debug('Found ' + talentPoolMembers.size() + ' candidates');
            
            if (talentPoolMembers.isEmpty()) {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse('No candidates found for the provided IDs')
                ));
                return;
            }
            
            // ✅ Step 5: Build name and email maps
            Set<Id> contactIds = new Set<Id>();
            
            for (CampaignMember member : talentPoolMembers) {
                contactIds.add(member.ContactId);
                contactNameMap.put(member.ContactId, member.Contact.Name);
                contactEmailMap.put(member.ContactId, member.Contact.Email);
            }
            
            // ✅ Step 6: Check for existing Campaign Members in target campaign
            Set<Id> existingContactIds = new Set<Id>();
            List<CampaignMember> existingMembers = [
                SELECT Id, ContactId
                FROM CampaignMember
                WHERE CampaignId = :campaignId AND ContactId IN :contactIds
            ];
            
            for (CampaignMember existing : existingMembers) {
                existingContactIds.add(existing.ContactId);
                System.debug('⚠ Contact already in campaign: ' + contactNameMap.get(existing.ContactId));
            }
            
            // ✅ Step 7: Build list of NEW Campaign Members to create
            List<CampaignMember> newCampaignMembers = new List<CampaignMember>();
            
            for (Id contactId : contactIds) {
                // Skip if already exists
                if (existingContactIds.contains(contactId)) {
                    continue;
                }
                
                CampaignMember newMember = new CampaignMember();
                newMember.CampaignId = campaignId;
                newMember.ContactId = contactId;
                newMember.Status = campaignReq.status;
                
                newCampaignMembers.add(newMember);
            }
            
            System.debug('New campaign members to create: ' + newCampaignMembers.size());
            System.debug('Already existing: ' + existingContactIds.size());
            
            // ✅ Step 8: BULK INSERT - Create all new Campaign Members
            List<ExistingCampaignResult> campaignResults = new List<ExistingCampaignResult>();
            Integer successCount = 0;
            Integer failureCount = 0;
            
            if (!newCampaignMembers.isEmpty()) {
                Database.SaveResult[] saveResults = Database.insert(newCampaignMembers, false);
                
                System.debug('Insert results received: ' + saveResults.size());
                
                // Process results
                for (Integer i = 0; i < saveResults.size(); i++) {
                    Database.SaveResult sr = saveResults[i];
                    CampaignMember member = newCampaignMembers[i];
                    Id contactId = member.ContactId;
                    
                    ExistingCampaignResult result = new ExistingCampaignResult();
                    result.candidateId = member.Id;
                    result.candidateName = contactNameMap.get(contactId);
                    result.candidateEmail = contactEmailMap.get(contactId);
                    result.success = sr.isSuccess();
                    
                    if (sr.isSuccess()) {
                        result.campaignMemberId = sr.getId();
                        result.message = 'Added to campaign successfully';
                        successCount++;
                        System.debug('✓ Candidate added: ' + result.candidateName);
                    } else {
                        result.campaignMemberId = null;
                        result.message = sr.getErrors()[0].getMessage();
                        failureCount++;
                        System.debug('✗ Failed: ' + result.candidateName + ' | Error: ' + result.message);
                    }
                    
                    campaignResults.add(result);
                }
            } else {
                System.debug('ℹ No new members to add (all already in campaign)');
            }
            
            // ✅ Step 9: Add already-existing members to results
            for (CampaignMember existing : existingMembers) {
                ExistingCampaignResult result = new ExistingCampaignResult();
                result.candidateId = existing.Id;
                result.candidateName = contactNameMap.get(existing.ContactId);
                result.candidateEmail = contactEmailMap.get(existing.ContactId);
                result.success = true;
                result.campaignMemberId = existing.Id;
                result.message = 'Already member of this campaign';
                campaignResults.add(result);
            }
            
            System.debug('Success: ' + successCount + ', Failures: ' + failureCount + 
                        ', Already Existing: ' + existingContactIds.size());
            
            // ✅ Step 10: Build response
            ExistingCampaignResponse response = new ExistingCampaignResponse();
            response.campaignId = campaignId;
            response.campaignName = campaignName;
            response.campaignMemberStatus = campaignReq.status;
            response.totalProcessed = talentPoolMembers.size();
            response.successCount = successCount;
            response.failureCount = failureCount;
            response.alreadyMemberCount = existingContactIds.size();
            response.campaignResults = campaignResults;
            response.status = failureCount == 0 ? 'success' : 'partial_success';
            response.message = successCount + ' candidates added to "' + campaignName + '" (' + 
                              campaignReq.status + '), ' + existingContactIds.size() + 
                              ' already members, ' + failureCount + ' failed';
            
            res.statusCode = failureCount == 0 ? 200 : 207;
            res.responseBody = Blob.valueOf(JSON.serialize(response));
            
            System.debug('=== addToExistingCampaign COMPLETED SUCCESSFULLY ===');
            
        } catch (QueryException qe) {
            System.debug(LoggingLevel.ERROR, 'Campaign or candidate not found: ' + qe.getMessage());
            res.statusCode = 404;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('Campaign or candidate not found: ' + qe.getMessage())
            ));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'addToExistingCampaign error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse('Error adding candidates to campaign: ' + e.getMessage())
            ));
        }
    }
    
    
    /**
     * Helper: Transform CampaignMember to CandidateDTO
     */
    private static CandidateDTO transformToDTO(CampaignMember member) {
        Contact contact = member.Contact;
        CandidateDTO dto = new CandidateDTO();
        
        dto.id = member.Id;
        dto.realName = contact.Name;
        dto.anonymizedName = String.isNotBlank(contact.Anonymized_Name__c) 
            ? contact.Anonymized_Name__c 
            : 'Candidate ' + String.valueOf(member.Id).substring(0, 5);
        dto.role = contact.Job_Role__c;
        dto.matchScore = member.AI_Match_Score__c != null 
            ? Integer.valueOf(member.AI_Match_Score__c) 
            : 0;
        dto.matchStars = Math.floor(dto.matchScore / 20);
        dto.years = contact.Years_Experience__c != null 
            ? Integer.valueOf(contact.Years_Experience__c) 
            : 0;
        dto.location = buildLocation(contact.MailingCity, contact.MailingState, contact.MailingCountry);
        dto.skills = parseSkillsList(contact.R_ATS__Skills__c);
        dto.status = contact.Status__c ?? 'Active';
        dto.interest = contact.Interest_Notes__c;
        dto.availability = contact.Availability__c ?? 'Immediate';
        dto.salary = contact.Expected_Salary__c;
        dto.preference = contact.Work_Preference__c;
        dto.sentiment = contact.Candidate_Sentiment__c ?? 'Potential Fit';
        dto.notes = 'Candidate matched for your talent pool.';
        
        // Parse goals
        dto.goals = new Map<String, String>();
        dto.goals.put('shortTerm', contact.Short_Term_Goals__c ?? '');
        dto.goals.put('longTerm', contact.Long_Term_Goals__c ?? '');
        
        // Parse skill ratings from JSON
        dto.skillRatings = parseSkillRatings(contact.Skill_Ratings__c);
        
        // Generate match analysis
        dto.matchAnalysis = generateMatchAnalysis(contact.R_ATS__Skills__c, dto.matchScore);
        
        return dto;
    }
    
    /**
     * Helper: Build location string
     */
    private static String buildLocation(String city, String state, String country) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(city)) parts.add(city);
        if (String.isNotBlank(state)) parts.add(state);
        if (String.isNotBlank(country)) parts.add(country);
        return String.join(parts, ', ');
    }
    
    /**
     * Helper: Parse skills list from string
     */
    private static List<String> parseSkillsList(String skillsJson) {
        List<String> skills = new List<String>();
        if (String.isBlank(skillsJson)) return skills;
        
        try {
            // Try JSON format first
            List<Object> parsed = (List<Object>) JSON.deserializeUntyped(skillsJson);
            for (Object skill : parsed) {
                skills.add(String.valueOf(skill));
            }
        } catch (Exception e) {
            // Fall back to comma-separated
            for (String skill : skillsJson.split(',')) {
                String trimmed = skill.trim();
                if (String.isNotBlank(trimmed)) {
                    skills.add(trimmed);
                }
            }
        }
        
        return skills;
    }
    
    /**
     * Helper: Parse skill ratings from JSON
     */
    private static List<SkillRatingDTO> parseSkillRatings(String skillRatingsJson) {
        List<SkillRatingDTO> ratings = new List<SkillRatingDTO>();
        
        if (String.isBlank(skillRatingsJson)) return ratings;
        
        try {
            List<Map<String, Object>> parsed = (List<Map<String, Object>>) 
                JSON.deserializeUntyped(skillRatingsJson);
            
            for (Map<String, Object> rating : parsed) {
                SkillRatingDTO dto = new SkillRatingDTO();
                dto.name = String.valueOf(rating.get('name'));
                dto.level = Integer.valueOf(rating.get('level'));
                ratings.add(dto);
            }
        } catch (Exception e) {
            // If parsing fails, return empty list
            return ratings;
        }
        
        return ratings;
    }
    
    /**
     * Helper: Generate match analysis
     */
    private static List<MatchAnalysisDTO> generateMatchAnalysis(String skills, Integer matchScore) {
        List<MatchAnalysisDTO> analysis = new List<MatchAnalysisDTO>();
        
        List<String> skillsList = parseSkillsList(skills);
        
        for (String skill : skillsList) {
            MatchAnalysisDTO item = new MatchAnalysisDTO();
            item.label = skill + ' - ' + getLevelDescription(matchScore);
            item.status = matchScore >= 75 ? 'ok' : 'warning';
            analysis.add(item);
        }
        
        return analysis;
    }
    
    /**
     * Helper: Get skill level description
     */
    private static String getLevelDescription(Integer score) {
        if (score >= 90) return 'Expert level';
        if (score >= 75) return 'Advanced level';
        if (score >= 60) return 'Intermediate level';
        return 'Beginner level';
    }
    
    /**
     * Helper: Generate CSV export
     */
    private static String generateCSV(List<CampaignMember> members) {
        List<String> csvLines = new List<String>();
        
        // Header
        csvLines.add('Name,Anonymized Name,Role,Match Score,Years,Location,Skills,Status,Salary,Work Preference');
        
        // Data rows
        for (CampaignMember member : members) {
            Contact c = member.Contact;
            String location = buildLocation(c.MailingCity, c.MailingState, c.MailingCountry);
            String skillsStr = String.isNotBlank(c.R_ATS__Skills__c) ? c.R_ATS__Skills__c : '';
            String salary = String.isNotBlank(c.Expected_Salary__c) ? c.Expected_Salary__c : '';
            
            List<String> rowFields = new List<String>();
            rowFields.add(escapeCsvField(c.Name));
            rowFields.add(escapeCsvField(c.Anonymized_Name__c));
            rowFields.add(escapeCsvField(c.Job_Role__c));
            rowFields.add(String.valueOf(member.AI_Match_Score__c ?? 0));
            rowFields.add(String.valueOf(c.Years_Experience__c ?? 0));
            rowFields.add(escapeCsvField(location));
            rowFields.add(escapeCsvField(skillsStr));
            rowFields.add(escapeCsvField(c.Status__c));
            rowFields.add(escapeCsvField(salary));
            rowFields.add(escapeCsvField(c.Work_Preference__c));
            
            // Join row fields with comma
            String rowString = '';
            for (Integer i = 0; i < rowFields.size(); i++) {
                rowString += rowFields.get(i);
                if (i < rowFields.size() - 1) {
                    rowString += ',';
                }
            }
            csvLines.add(rowString);
        }
        
        // Join all lines with newline
        String csv = '';
        for (Integer i = 0; i < csvLines.size(); i++) {
            csv += csvLines.get(i);
            if (i < csvLines.size() - 1) {
                csv += '\n';
            }
        }
        
        return csv;
    }
    
    /**
     * Helper: Escape CSV field
     */
    private static String escapeCsvField(String field) {
        if (String.isBlank(field)) return '""';
        if (field.contains(',') || field.contains('"') || field.contains('\n')) {
            return '"' + field.replace('"', '""') + '"';
        }
        return field;
    }
    
    /**
     * Helper: Get sort field with case-insensitive matching
     */
    private static String getSortField(String sortBy) {
        // Default to matchScore if null or blank
        if (String.isBlank(sortBy)) {
            System.debug('sortBy is blank, using default: matchScore');
            return 'AI_Match_Score__c';
        }
        
        // Normalize to lowercase for comparison
        String normalizedSort = sortBy.toLowerCase().trim();
        
        System.debug('Normalized sortBy: ' + normalizedSort);
        
        switch on normalizedSort {
            when 'matchscore' {
                return 'AI_Match_Score__c';
            }
            when 'years' {
                return 'Contact.Years_Experience__c';
            }
            when 'name' {
                return 'Contact.Anonymized_Name__c';
            }
            when else {
                System.debug('Unknown sortBy value: ' + normalizedSort + ', using default');
                return 'AI_Match_Score__c';
            }
        }
    }
    
    /**
     * Helper: Validate that accountId exists in Registration_Request__c
     */
    private static Boolean validateEmployerAccount(Id accountId) {
        if (accountId == null) {
            System.debug(LoggingLevel.WARN, '✗ Account ID is null');
            return false;
        }
        
        try {
            Registration_Request__c regRequest = [
                SELECT Id, Account__c, Account__r.Name
                FROM Registration_Request__c 
                WHERE Account__c = :accountId
                LIMIT 1
            ];
            
            System.debug('✓ Account validated: ' + accountId);
            System.debug('✓ Account Name: ' + regRequest.Account__r.Name);
            return true;
            
        } catch (QueryException e) {
            System.debug(LoggingLevel.WARN, '✗ Account not found in Registration_Request: ' + accountId);
            return false;
        }
    }
    
    /**
     * Helper: Handle exceptions
     */
    private static void handleException(Exception e) {
        RestContext.response.statusCode = 500;
        ErrorResponse errorRes = new ErrorResponse(
            'Internal server error: ' + e.getMessage()
        );
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(errorRes));
        
        // Log error
        System.debug(LoggingLevel.ERROR, 'CandidateAPI Exception: ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
    }
    
    // ==================== DTO Classes ====================
    
    global class CandidateDTO {
        public String id;
        public String realName;
        public String anonymizedName;
        public String role;
        public Integer matchScore;
        public Decimal matchStars;
        public Integer years;
        public String location;
        public List<String> skills;
        public String status;
        public String interest;
        public Map<String, String> goals;
        public String availability;
        public String salary;
        public String preference;
        public String sentiment;
        public String notes;
        public List<SkillRatingDTO> skillRatings;
        public List<MatchAnalysisDTO> matchAnalysis;
    }
    
        
    /**
     * ⭐ NEW DTO CLASS #1: Campaign Data Transfer Object
     */
    global class CampaignDTO {
        public String id;
        public String name;
        public String status;
        public String description;
        public String startDate;
        public String recordTypeName;
        public Integer memberCount;
    }
    
    /**
     * ⭐ NEW DTO CLASS #2: Campaign List Response for GET /api/candidates/campaigns
     */
    global class CampaignListResponse {
        public List<CampaignDTO> campaigns;
        public Integer totalCount;
        public String status;
        
        public CampaignListResponse(List<CampaignDTO> campaigns, Integer totalCount, String status) {
            this.campaigns = campaigns;
            this.totalCount = totalCount;
            this.status = status;
        }
    }
    
    /**
     * ⭐ NEW DTO CLASS #3: Request class for adding candidates to EXISTING campaign
     */
    global class ExistingCampaignRequest {
        public String accountId;              // Employer Account ID (required)
        public List<Id> candidateIds;         // List of CampaignMember IDs (required)
        public String campaignId;             // Existing Campaign ID (required)
        public String status;                 // Campaign Member status (required)
    }
    
    /**
     * ⭐ NEW DTO CLASS #4: Individual result for each candidate added to existing campaign
     */
    global class ExistingCampaignResult {
        public String candidateId;            // CampaignMember ID
        public String candidateName;          // Candidate name
        public String candidateEmail;         // Candidate email
        public Boolean success;               // true if successfully added
        public String campaignMemberId;       // Campaign Member ID (if success)
        public String message;                // Success/error message
    }
    
    /**
     * ⭐ NEW DTO CLASS #5: Response class for add to existing campaign operation
     */
    global class ExistingCampaignResponse {
        public String campaignId;             // Campaign ID
        public String campaignName;           // Campaign name
        public String campaignMemberStatus;   // Status assigned to campaign members
        public Integer totalProcessed;        // Total candidates processed
        public Integer successCount;          // Successfully added
        public Integer failureCount;          // Failed to add
        public Integer alreadyMemberCount;    // Already members of campaign
        public List<ExistingCampaignResult> campaignResults;
        public String status;                 // 'success', 'partial_success', 'error'
        public String message;                // Summary message
    }
    
    /**
     * ⭐ NEW DTO CLASS #6: Validation result for campaign selection
     */
    global class ValidationResult {
        public Boolean isValid;               // Is validation successful
        public String campaignId;             // Campaign ID (if valid)
        public String campaignName;           // Campaign name (if valid)
        public String status;                 // Campaign status (if valid)
        public String errorMessage;           // Error message (if invalid)
        public String message;                // Success message
    }
    
     /**
     * Request class for email sending
     */
    global class EmailRequest {
        public String accountId;              // Employer Account ID
        public String candidateId;            // CampaignMember ID
        public String to;                     // Recipient email (required)
        public String cc;                     // CC emails (comma-separated, optional)
        public String bcc;                    // BCC emails (comma-separated, optional)
        public String subject;                // Email subject (required)
        public String body;                   // Email body/message (required)
        public List<AttachmentData> attachments;  // Base64-encoded files (optional)
        public Boolean bccSender;             // Add sender to BCC (optional)
    }
    
    global class AttachmentData {
        public String filename;               // File name with extension (e.g., "offer.pdf")
        public String content;                // Base64-encoded file content
        public String contentType;            // MIME type (e.g., "application/pdf", "text/plain")
    }
    
    /**
     * Response class for email sending success
     */
    global class EmailResponse {
        public Boolean success;               // true if email sent successfully
        public String message;                // Success/error message
        public String taskId;                 // Salesforce Task ID for activity tracking
        public String timestamp;              // ISO 8601 timestamp when sent
        public String sender;                 // From email address
        public String recipient;              // To email address
        public String candidateId;            // CampaignMember ID
        public String status;                 // 'delivered', 'failed', 'pending'
        public Integer attachmentCount;
    }
    
     /**
     * Request class for adding candidates to campaign
     */
    global class AddToCampaignRequest {
        public String accountId;              // Employer Account ID
        public List<Id> candidateIds;     // List of CampaignMember IDs
        public String campaignId;             // Existing Campaign ID (optional)
        public String campaignName;           // New Campaign name (optional)
        public String status;                 // Campaign Member status (required) - e.g., 'Interested', 'Sent', etc.
        public String position;               // Job Position/Role (optional)
    }
    
    /**
     * Individual result for each candidate added to campaign
     */
    global class AddToCampaignResult {
        public String candidateId;            // CampaignMember ID
        public String candidateName;          // Candidate name
        public Boolean success;               // true if successfully added
        public String campaignMemberId;       // New Campaign Member ID (if success)
        public String message;                // Success/error message
    }
    
    /**
     * Response class for add to campaign operation
     */
    global class AddToCampaignResponse {
        public String campaignId;             // Campaign ID (new or existing)
        public String campaignName;           // Campaign name
        public Integer totalProcessed;        // Total candidates processed
        public Integer successCount;          // Successfully added
        public Integer failureCount;          // Failed to add
        public Integer alreadyMemberCount;    // Already members of campaign
        public List<AddToCampaignResult> campaignResults;  // Detailed results per candidate
        public String status;                 // 'success', 'partial_success', 'error'
        public String message;                // Summary message
    }
    
    global class SkillRatingDTO {
        public String name;
        public Integer level;
    }
    
    global class MatchAnalysisDTO {
        public String label;
        public String status;
    }
    
    global class CandidateListResponse {
        public List<CandidateDTO> candidates;
        public Integer totalCount;
        public Integer pageNumber;
        public Integer pageSize;
        public String status;
        
        public CandidateListResponse(List<CandidateDTO> candidates, Integer totalCount, 
                                    Integer pageNumber, Integer pageSize, String status) {
            this.candidates = candidates;
            this.totalCount = totalCount;
            this.pageNumber = pageNumber;
            this.pageSize = pageSize;
            this.status = status;
        }
    }
    
    global class BulkActionRequest {
        public String accountId;
        public List<String> candidateIds;
        public String action; // 'updateStatus', 'delete'
        public String status; // For updateStatus action
    }
    
    global class BulkActionResponse {
        public Integer count;
        public String message;
        public String status;
        
        public BulkActionResponse(Integer count, String message, String status) {
            this.count = count;
            this.message = message;
            this.status = status;
        }
    }
    
    global class ExportRequest {
        public String accountId;
        public List<String> candidateIds;
        public String format; // 'csv', 'json'
    }
    
    global class InterviewRequest {
        public String accountId;
        public List<String> candidateIds;           // CampaignMember ID
        public String interviewFormat;       // Phone Interview, Video Interview, In-Person Interview
        public String position;              // Job Position/Role
        public String interviewRound;        // Optional: First Round, Technical, etc.
        public String duration;              // Optional: 30 min, 60 min, etc.
        public String message;               // Optional: Additional message for candidate
    }
    
     /**
     * New: Individual task result for each candidate
     */
    global class InterviewTaskResult {
        public String candidateId;
        public String candidateName;
        public Boolean success;
        public String taskId;
        public String message;
    }
    
    /**
     * New: Bulk interview response with detailed results
     */
    global class BulkInterviewResponse {
        public Integer totalRequested;
        public Integer successCount;
        public Integer failureCount;
        public List<InterviewTaskResult> taskResults;
        public String status;              // 'success', 'partial_success', 'error'
        public String message;
    }
    
    global class InterviewResponse {
        public String taskId;
        public String message;
        public String status;
        
        public InterviewResponse(String taskId, String message, String status) {
            this.taskId = taskId;
            this.message = message;
            this.status = status;
        }
    }
    
    global class ErrorResponse {
        public String error;
        public String status;
        
        public ErrorResponse(String error) {
            this.error = error;
            this.status = 'error';
        }
    }
}