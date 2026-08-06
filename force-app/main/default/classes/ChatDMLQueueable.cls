/*
----------------------------------------------------------------------------
ChatDMLQueueable.cls - CREATES NEW CAREER INTENT PER SESSION
All database writes happen here in background
Creates NEW Career_Intent__c record when all data collected
FIXED: Correct signal detection based on PREVIOUS question
----------------------------------------------------------------------------
*/
public class ChatDMLQueueable implements Queueable, Database.AllowsCallouts {

    private String sessionId;
    private String contactId;
    private String userMessage;
    private String assistantMessage;
    private String contextType;
    private Integer tokenCount;
    private Long responseTime;
    private String aiModel;
    private Boolean needsDataCopy;  // NEW: Flag for copying existing data
    private Boolean saveIntent;
    private String answeredQuestionCount;

    public ChatDMLQueueable(String sessionId, String contactId,
                            String userMessage, String assistantMessage,
                            String contextType, Integer tokenCount,
                            Long responseTime, String aiModel, Boolean needsDataCopy) {
        this(
            sessionId,
            contactId,
            userMessage,
            assistantMessage,
            contextType,
            tokenCount,
            responseTime,
            aiModel,
            needsDataCopy,
            true
        );
    }

    public ChatDMLQueueable(String sessionId, String contactId,
                            String userMessage, String assistantMessage,
                            String contextType, Integer tokenCount,
                            Long responseTime, String aiModel, Boolean needsDataCopy,
                            Boolean saveIntent) {
        this(
            sessionId,
            contactId,
            userMessage,
            assistantMessage,
            contextType,
            tokenCount,
            responseTime,
            aiModel,
            needsDataCopy,
            saveIntent,
            null
        );
    }

    public ChatDMLQueueable(String sessionId, String contactId,
                            String userMessage, String assistantMessage,
                            String contextType, Integer tokenCount,
                            Long responseTime, String aiModel, Boolean needsDataCopy,
                            Boolean saveIntent, String answeredQuestionCount) {
        this.sessionId = sessionId;
        this.contactId = contactId;
        this.userMessage = userMessage;
        this.assistantMessage = assistantMessage;
        this.contextType = contextType;
        this.tokenCount = tokenCount;
        this.responseTime = responseTime;
        this.aiModel = aiModel;
        this.needsDataCopy = needsDataCopy != null ? needsDataCopy : false;
        this.saveIntent = saveIntent != null ? saveIntent : true;
        this.answeredQuestionCount = answeredQuestionCount;
    }

    public void execute(QueueableContext qc) {
        Savepoint sp = Database.setSavepoint();

        try {
            DateTime now = DateTime.now();

            // ============ DML 1: Bulk Insert Both Messages ============
            List<Chat_Interaction__c> messages = new List<Chat_Interaction__c>();

            // User message
            messages.add(new Chat_Interaction__c(
                Contact__c = contactId,
                Session_ID__c = sessionId,
                Message_Type__c = 'User',
                Message_Content__c = truncateMessage(userMessage),
                Context_Type__c = contextType,
                Timestamp__c = now.addSeconds(-1),
                Started_At__c = now
            ));

            // Assistant message (clean any input markers before storing)
            String cleanedAssistantMsg = cleanInputMarkers(assistantMessage);
            messages.add(new Chat_Interaction__c(
                Contact__c = contactId,
                Session_ID__c = sessionId,
                Message_Type__c = 'Assistant',
                Message_Content__c = truncateMessage(cleanedAssistantMsg),
                Context_Type__c = contextType,
                Timestamp__c = now,
                Total_Tokens__c = tokenCount,
                Response_Time_ms__c = String.valueOf(responseTime),
                AI_Model__c = aiModel,
                Started_At__c = now
            ));

            insert messages;

            // ============ DML 2: Copy existing data if needed (BEFORE extraction) ============
            if (needsDataCopy) {
                copyExistingDataToNewSession(contactId, sessionId);
            }

            // ============ DML 3: Extract & Update Session Career Intent ============
            if (saveIntent && shouldExtractIntent(contextType)) {
                extractAndUpdateSessionIntent(contactId, sessionId, userMessage, cleanedAssistantMsg, answeredQuestionCount);
            }

            // ============ DML 4: Update Contact Timestamp ============
            updateContactTimestamp(contactId, now);

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, 'ChatDMLQueueable Error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            insertErrorLog('ChatDMLQueueable', e.getMessage(), e.getStackTraceString(), contactId);
        }
    }

    // Extract intent and update/create single candidate intent record
    private void extractAndUpdateSessionIntent(String contactId, String sessionId, String userMsg, String aiMsg, String answeredQuestionCount) {
        if (String.isNotBlank(answeredQuestionCount)) {
            Career_Intent__c mappedIntent = getSessionIntent(contactId, sessionId);
            Boolean mappedChanged = saveByQuestionCount(mappedIntent, userMsg, answeredQuestionCount);
            if (mappedChanged) {
                mappedIntent.Contact__c = contactId;
                mappedIntent.Candidate__c = contactId;
                mappedIntent.Last_Check_In__c = DateTime.now();
                upsert mappedIntent;
                syncContactSalary(contactId, mappedIntent.Min_Salary_Expactation__c, mappedIntent.Max_Salary_Expactation__c);
                syncContactSkills(contactId, mappedIntent.Skills__c);
                if (Integer.valueOf(answeredQuestionCount) <= 4) {
                    CareerPathwaySyncService.syncForIntent(mappedIntent.Id);
                }
                BlakeneyInteractionEventService.publish(
                    parseId(contactId),
                    Integer.valueOf(answeredQuestionCount) <= 4 ? 'Goal Update' : 'Profile Update',
                    'Career_Intent__c question ' + answeredQuestionCount,
                    mappedIntent.Id,
                    null,
                    sessionId
                );
                System.debug('Updated Career Intent by questionCount ' + answeredQuestionCount + ' for session: ' + sessionId);
            }
            return;
        }

        // CRITICAL: Skip if this is a resume decision response
        if (isResumeDecision(userMsg) && !hasRemotePreferenceSignal(aiMsg)) {
            System.debug('â­ï¸ Skipping save - this is a resume decision, not a career answer');
            return;
        }

        // Get or create one intent for this candidate. Existing fields stay untouched unless this answer updates them.
        Career_Intent__c intent = getSessionIntent(contactId, sessionId);

        Boolean changed = false;


        // FIXED: Check what question was JUST ANSWERED (in AI's next response)
        // The AI asks the NEXT question, so user just answered the PREVIOUS one

        // Short-term goal (6 months) - AI asks about 2-5 years next
        if (hasMediumTermSignal(aiMsg)) {
            String extracted = cleanMessage(userMsg);
            if (String.isNotBlank(extracted)) {
                intent.Short_Term_Goal__c = extracted;
                changed = true;
                System.debug('âœ… Saved Short-term goal: ' + extracted);
            }
        }

        // Medium-term goal (2-5 years) - AI asks about 10+ years next
        else if (hasLongTermSignal(aiMsg)) {
            String extracted = cleanMessage(userMsg);
            if (String.isNotBlank(extracted)) {
                intent.Medium_Term_Goal__c = extracted;
                changed = true;
                System.debug('âœ… Saved Medium-term goal: ' + extracted);
            }
        }

        // Long-term goal (10+ years) - AI asks about dream job next
        else if (hasAspirationalSignal(aiMsg)) {
            String extracted = cleanMessage(userMsg);
            if (String.isNotBlank(extracted)) {
                intent.Long_Term_Goal__c = extracted;
                changed = true;
                System.debug('âœ… Saved Long-term goal: ' + extracted);
            }
        }

        // Aspirational goal (dream job) - AI asks about location next
        else if (hasRelocatingSignal(aiMsg)) {
            String extracted = cleanMessage(userMsg);
            if (String.isNotBlank(extracted)) {
                intent.Aspirational_Goal__c = extracted;
                changed = true;
                System.debug('âœ… Saved Aspirational goal: ' + extracted);
            }
        }

        // Willing to relocate - AI asks about remote preference next
        else if (hasRemotePreferenceSignal(aiMsg)) {
            String extracted = userMsg;
            if (String.isNotBlank(extracted)) {
                intent.Willing_to_Relocate__c = extracted;
                changed = true;
                System.debug('âœ… Saved Work location: ' + extracted);
            }
        }

        // Remote preference - AI asks about minimum salary next
        else if (hasMinSalarySignal(aiMsg)) {
            String extracted = userMsg;
            if (String.isNotBlank(extracted)) {
                intent.Short_Term_Remote__c = extracted;
                changed = true;
                System.debug('âœ… Saved Remote preference: ' + extracted);
            }
        }

        // Minimum salary - AI asks about maximum salary next
        else if (hasMaxSalarySignal(aiMsg)) {
            String extracted = userMsg;
            if (String.isNotBlank(extracted)) {
                intent.Min_Salary_Expactation__c = normalizeSalary(extracted);
                changed = true;
                System.debug('âœ… Saved Minimum salary: ' + extracted);
            }
        }

        // Maximum salary - AI asks about company size next
        else if (hasCompanySizePreferenceSignal(aiMsg)) {
            String extracted = userMsg;
            if (String.isNotBlank(extracted)) {
                intent.Max_Salary_Expactation__c = normalizeSalary(extracted);
                changed = true;
                System.debug('âœ… Saved Maximum salary: ' + extracted);
            }
        }

        // Company size - AI asks about industry next
        else if (hasIndustryPreferenceSignal(aiMsg)) {
            String extracted = userMsg;
            if (String.isNotBlank(extracted)) {
                intent.Short_Term_Company_Size__c = extracted;
                changed = true;
                System.debug('âœ… Saved Company size: ' + extracted);
            }
        }

        // Industry preferences - AI asks about current role next
        else if (hasCurrentRoleSignal(aiMsg)) {
            String extracted = cleanMessage(userMsg);
            if (String.isNotBlank(extracted)) {
                intent.Industry_Preferences__c = extracted;
                changed = true;
                System.debug('âœ… Saved Industry preferences: ' + extracted);
            }
        }

        // Current role - AI says profile complete next
        else if (hasCompletionSignal(aiMsg)) {
            String extracted = cleanMessage(userMsg);
            if (String.isNotBlank(extracted)) {
                intent.Role_Title__c = extracted;
                changed = true;
                System.debug('âœ… Saved Current role: ' + extracted);
            }
        }

        if (changed) {
            intent.Contact__c = contactId;
            intent.Candidate__c = contactId;
            intent.Last_Check_In__c = DateTime.now();
            upsert intent;
            syncContactSalary(contactId, intent.Min_Salary_Expactation__c, intent.Max_Salary_Expactation__c);
            syncContactSkills(contactId, intent.Skills__c);
            if (hasMediumTermSignal(aiMsg) || hasLongTermSignal(aiMsg) || hasAspirationalSignal(aiMsg) || hasRelocatingSignal(aiMsg)) {
                CareerPathwaySyncService.syncForIntent(intent.Id);
            }
            BlakeneyInteractionEventService.publish(
                parseId(contactId),
                hasCompletionSignal(aiMsg) ? 'Onboarding' : 'Profile Update',
                'Career_Intent__c conversation update',
                intent.Id,
                null,
                sessionId
            );
            System.debug('âœ… Updated Career Intent for session: ' + sessionId);
        }
    }

    private Boolean saveByQuestionCount(Career_Intent__c intent, String userMsg, String answeredQuestionCount) {
        Integer questionNumber;
        try {
            questionNumber = Integer.valueOf(answeredQuestionCount);
        } catch (Exception e) {
            return false;
        }

        String cleaned = cleanMessage(userMsg);
        if (String.isBlank(cleaned)) return false;

        if (questionNumber == 1) {
            intent.Short_Term_Goal__c = cleaned;
            return true;
        }
        if (questionNumber == 2) {
            intent.Medium_Term_Goal__c = cleaned;
            return true;
        }
        if (questionNumber == 3) {
            intent.Long_Term_Goal__c = cleaned;
            return true;
        }
        if (questionNumber == 4) {
            intent.Aspirational_Goal__c = cleaned;
            return true;
        }
        if (questionNumber == 5) {
            intent.Willing_to_Relocate__c = userMsg;
            return true;
        }
        if (questionNumber == 6) {
            intent.Short_Term_Remote__c = userMsg;
            return true;
        }
        if (questionNumber == 7) {
            intent.Min_Salary_Expactation__c = normalizeSalary(userMsg);
            return intent.Min_Salary_Expactation__c != null;
        }
        if (questionNumber == 8) {
            intent.Max_Salary_Expactation__c = normalizeSalary(userMsg);
            return intent.Max_Salary_Expactation__c != null;
        }
        if (questionNumber == 9) {
            intent.Short_Term_Company_Size__c = userMsg;
            return true;
        }
        if (questionNumber == 10) {
            intent.Industry_Preferences__c = cleaned;
            return true;
        }
        if (questionNumber == 11) {
            intent.Role_Title__c = cleaned;
            return true;
        }
        if (questionNumber == 12) {
            intent.Skills__c = mergeSkillText(null, cleaned);
            return true;
        }

        return false;
    }

    // Get latest candidate intent. Create only when candidate has no existing intent.
    private Career_Intent__c getSessionIntent(String contactId, String sessionId) {
        lockCandidateContact(contactId);
        List<Career_Intent__c> intents = [
            SELECT Id, Contact__c, Candidate__c, Session_ID__c,
                   Short_Term_Goal__c, Medium_Term_Goal__c, Long_Term_Goal__c,
                   Aspirational_Goal__c, Willing_to_Relocate__c, Short_Term_Remote__c,
                   Min_Salary_Expactation__c, Max_Salary_Expactation__c,
                   Short_Term_Company_Size__c, Industry_Preferences__c, Role_Title__c,
                   Skills__c
            FROM Career_Intent__c
            WHERE Contact__c = :contactId OR Candidate__c = :contactId
            ORDER BY LastModifiedDate DESC
            // AND Session_ID__c = :sessionId
            LIMIT 1
        ];

        if (!intents.isEmpty()) {
            if (intents[0].Contact__c == null) {
                intents[0].Contact__c = contactId;
            }
            if (intents[0].Candidate__c == null) {
                intents[0].Candidate__c = contactId;
            }
            return intents[0];
        }

        // Create new intent for this session
        Career_Intent__c newIntent = new Career_Intent__c();
        newIntent.Contact__c = contactId;
        newIntent.Candidate__c = contactId;
        newIntent.Session_ID__c = sessionId;
        return newIntent;
    }

    private void lockCandidateContact(String contactId) {
        if (String.isBlank(contactId)) {
            return;
        }

        try {
            List<Contact> locks = [
                SELECT Id
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
                FOR UPDATE
            ];
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Unable to lock Contact before intent save: ' + e.getMessage());
        }
    }

    private String mergeSkillText(String existingSkills, String incomingSkills) {
        Set<String> seen = new Set<String>();
        List<String> merged = new List<String>();
        addSkills(merged, seen, incomingSkills);
        return merged.isEmpty() ? null : String.join(merged, ', ');
    }

    private void addSkills(List<String> merged, Set<String> seen, String skillsText) {
        if (String.isBlank(skillsText)) return;
        for (String rawSkill : skillsText.split('[,;\\n]+')) {
            String skill = rawSkill == null ? '' : rawSkill.trim();
            if (String.isBlank(skill)) continue;
            String key = skill.toLowerCase();
            if (seen.contains(key)) continue;
            seen.add(key);
            merged.add(skill);
        }
    }

    // Check if message is a resume decision (not a real career answer)
    private Boolean isResumeDecision(String message) {
        if (String.isBlank(message)) return false;
        String lower = message.toLowerCase();

        // Resume decision keywords
        return lower.contains('update information') ||
               lower.contains('continue where i left off') ||
               lower.contains('update') && lower.length() < 20 ||
               lower.contains('continue') && lower.length() < 20 ||
               lower.equals('yes') ||
               lower.equals('no');
    }

    // Keep current session synced to the single candidate Career Intent record
    private void copyExistingDataToNewSession(String contactId, String sessionId) {
        try {
            System.debug('ðŸ“‹ Starting data copy for session: ' + sessionId);

            // Get latest existing intent (not from current session)
            List<Career_Intent__c> existingIntents = [
                SELECT Id, Contact__c, Candidate__c, Short_Term_Goal__c, Medium_Term_Goal__c, Long_Term_Goal__c,
                       Aspirational_Goal__c, Willing_to_Relocate__c, Short_Term_Remote__c,
                       Min_Salary_Expactation__c, Max_Salary_Expactation__c,
                       Short_Term_Company_Size__c, Industry_Preferences__c, Role_Title__c
                FROM Career_Intent__c
                WHERE Contact__c = :contactId OR Candidate__c = :contactId
                // AND Session_ID__c != :sessionId
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];

            if (existingIntents.isEmpty()) {
                System.debug('âš ï¸ No existing intent found to copy from');
                return;
            }

            Career_Intent__c existingIntent = existingIntents[0];

            // Check if current session already has an intent record
            List<Career_Intent__c> currentSessionIntents = [
                SELECT Id, Contact__c, Candidate__c, Short_Term_Goal__c, Medium_Term_Goal__c, Long_Term_Goal__c,
                       Aspirational_Goal__c, Willing_to_Relocate__c, Short_Term_Remote__c,
                       Min_Salary_Expactation__c, Max_Salary_Expactation__c,
                       Short_Term_Company_Size__c, Industry_Preferences__c, Role_Title__c
                FROM Career_Intent__c
                WHERE Contact__c = :contactId OR Candidate__c = :contactId
                ORDER BY LastModifiedDate DESC
                // AND Session_ID__c = :sessionId
                LIMIT 1
            ];

            Career_Intent__c newIntent;

            if (currentSessionIntents.isEmpty()) {
                // Create new record for current session
                newIntent = new Career_Intent__c();
                newIntent.Contact__c = contactId;
                newIntent.Candidate__c = contactId;
                newIntent.Session_ID__c = sessionId;
            } else {
                // Use existing record
                newIntent = currentSessionIntents[0];
            }

            // Copy all filled fields from existing intent
            if (String.isNotBlank(existingIntent.Short_Term_Goal__c)) {
                newIntent.Short_Term_Goal__c = existingIntent.Short_Term_Goal__c;
            }
            if (String.isNotBlank(existingIntent.Medium_Term_Goal__c)) {
                newIntent.Medium_Term_Goal__c = existingIntent.Medium_Term_Goal__c;
            }
            if (String.isNotBlank(existingIntent.Long_Term_Goal__c)) {
                newIntent.Long_Term_Goal__c = existingIntent.Long_Term_Goal__c;
            }
            if (String.isNotBlank(existingIntent.Aspirational_Goal__c)) {
                newIntent.Aspirational_Goal__c = existingIntent.Aspirational_Goal__c;
            }
            if (String.isNotBlank(existingIntent.Willing_to_Relocate__c)) {
                newIntent.Willing_to_Relocate__c = existingIntent.Willing_to_Relocate__c;
            }
            if (String.isNotBlank(existingIntent.Short_Term_Remote__c)) {
                newIntent.Short_Term_Remote__c = existingIntent.Short_Term_Remote__c;
            }
            if (existingIntent.Min_Salary_Expactation__c != null) {
                newIntent.Min_Salary_Expactation__c = existingIntent.Min_Salary_Expactation__c;
            }
            if (existingIntent.Max_Salary_Expactation__c != null) {
                newIntent.Max_Salary_Expactation__c = existingIntent.Max_Salary_Expactation__c;
            }
            if (String.isNotBlank(existingIntent.Short_Term_Company_Size__c)) {
                newIntent.Short_Term_Company_Size__c = existingIntent.Short_Term_Company_Size__c;
            }
            if (String.isNotBlank(existingIntent.Industry_Preferences__c)) {
                newIntent.Industry_Preferences__c = existingIntent.Industry_Preferences__c;
            }
            if (String.isNotBlank(existingIntent.Role_Title__c)) {
                newIntent.Role_Title__c = existingIntent.Role_Title__c;
            }

            newIntent.Contact__c = contactId;
            newIntent.Candidate__c = contactId;
            newIntent.Last_Check_In__c = DateTime.now();

            // Upsert the record
            upsert newIntent;
            syncContactSalary(contactId, newIntent.Min_Salary_Expactation__c, newIntent.Max_Salary_Expactation__c);

            System.debug('âœ… Copied existing data to new session record');
            System.debug('   - Copied from: ' + existingIntent.Id);
            System.debug('   - Copied to: ' + newIntent.Id);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'âŒ Failed to copy existing data: ' + e.getMessage());
        }
    }

    // FIXED SIGNAL DETECTION: What question is AI asking NEXT?
    // This tells us what the user JUST answered

    // AI asks about 2-5 years â†’ User just answered about 6 months (short-term)
    private Boolean hasMediumTermSignal(String text) {
        if (String.isBlank(text)) return false;
        String t = text.toLowerCase();
        return t.contains('2-5 years') ;
    }

    // AI asks about 10+ years â†’ User just answered about 2-5 years (medium-term)
    private Boolean hasLongTermSignal(String text) {
        if (String.isBlank(text)) return false;
        String t = text.toLowerCase();
        return t.contains('long-term') || t.contains('10+ years') || t.contains('10 years');
    }

    // AI asks about dream job â†’ User just answered about 10+ years (long-term)
    private Boolean hasAspirationalSignal(String text) {
        if (String.isBlank(text)) return false;
        String t = text.toLowerCase();
        return t.contains('dream') || t.contains('ideal') ||
               t.contains('absolute dream role');
    }

    // AI asks about relocating â†’ User just answered about dream job (aspirational)
    private Boolean hasRelocatingSignal(String text) {
        if (String.isBlank(text)) return false;
        String t = text.toLowerCase();
        return t.contains('where would you like to work') ||
               t.contains('open to relocat') || t.contains('prefer to stay');
    }

    // AI asks about remote work â†’ User just answered about relocation
    private Boolean hasRemotePreferenceSignal(String text) {
        if (String.isBlank(text)) return false;
        String t = text.toLowerCase();
        return t.contains('remote work') || t.contains('preference for remote');
    }

    // AI asks about minimum salary â†’ User just answered about remote preference
    private Boolean hasMinSalarySignal(String text) {
        if (String.isBlank(text)) return false;
        String t = text.toLowerCase();
        return t.contains('minimum salary');
    }

    // AI asks about maximum salary â†’ User just answered about minimum salary
    private Boolean hasMaxSalarySignal(String text) {
        if (String.isBlank(text)) return false;
        String t = text.toLowerCase();
        return t.contains('maximum salary');
    }

    // AI asks about company size â†’ User just answered about maximum salary
    private Boolean hasCompanySizePreferenceSignal(String text) {
        if (String.isBlank(text)) return false;
        String t = text.toLowerCase();
        return t.contains('size company') || t.contains('company do you prefer');
    }

    // AI asks about industries â†’ User just answered about company size
    private Boolean hasIndustryPreferenceSignal(String text) {
        if (String.isBlank(text)) return false;
        String t = text.toLowerCase();
        return t.contains('industries are you') || t.contains('what industries');
    }

    // AI asks about current role â†’ User just answered about industries
    private Boolean hasCurrentRoleSignal(String text) {
        if (String.isBlank(text)) return false;
        String t = text.toLowerCase();
        return t.contains('current role') || t.contains('what is your current');
    }

    // AI says completion â†’ User just answered about current role
    private Boolean hasCompletionSignal(String text) {
        if (String.isBlank(text)) return false;
        String t = text.toLowerCase();
        return t.contains('profile is') || t.contains('complete') ||
               t.contains('all set') || t.contains('thank');
    }

    // Normalize salary
    private Integer normalizeSalary(String input) {
        if (String.isBlank(input)) return null;
        String cleaned = input.replace('$', '').replace(',', '').trim();
        try {
            return Integer.valueOf(cleaned);
        } catch (Exception e) {
            return null;
        }
    }

    private void syncContactSalary(String contactId, Decimal minSalaryValue, Decimal maxSalaryValue) {
        if (String.isBlank(contactId) || (minSalaryValue == null && maxSalaryValue == null)) {
            return;
        }

        try {
            List<Contact> contacts = [
                SELECT Id, R_ATS__Minimum_Salary__c, R_ATS__Maximum_Salary__c
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
            ];
            if (contacts.isEmpty()) return;

            Contact currentContact = contacts[0];
            Contact updateContact = new Contact(Id = currentContact.Id);
            Boolean changed = false;

            if (minSalaryValue != null && currentContact.R_ATS__Minimum_Salary__c != minSalaryValue) {
                updateContact.R_ATS__Minimum_Salary__c = minSalaryValue;
                changed = true;
            }
            if (maxSalaryValue != null && currentContact.R_ATS__Maximum_Salary__c != maxSalaryValue) {
                updateContact.R_ATS__Maximum_Salary__c = maxSalaryValue;
                changed = true;
            }

            if (changed) {
                update updateContact;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to sync Contact salary from Career Intent: ' + e.getMessage());
        }
    }

    private void syncContactSkills(String contactId, String skillsText) {
        if (String.isBlank(contactId) || String.isBlank(skillsText)) {
            return;
        }

        try {
            List<Contact> contacts = [
                SELECT Id, R_ATS__Skills__c
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
            ];
            if (contacts.isEmpty() || contacts[0].R_ATS__Skills__c == skillsText) return;

            update new Contact(Id = contacts[0].Id, R_ATS__Skills__c = skillsText);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to sync Contact skills from Career Intent: ' + e.getMessage());
        }
    }

    private Id parseId(String value) {
        if (String.isBlank(value)) return null;
        try {
            return (Id) value;
        } catch (Exception e) {
            return null;
        }
    }

    // Clean message
    private String cleanMessage(String msg) {
        if (String.isBlank(msg)) return null;
        String cleaned = msg.trim();
        cleaned = cleaned.replaceAll('(?i)^(well|so|um|like|basically),?\\s*', '');
        return cleaned.length() > 5000 ? cleaned.substring(0, 5000) : cleaned;
    }

    // Clean input markers from message before storing
    private String cleanInputMarkers(String message) {
        if (String.isBlank(message)) return message;
        return message.replaceAll('\\[INPUT:(TEXT|NUMBER|DATE|NONE)\\]', '').trim();
    }

    // Check if intent extraction should run
    private Boolean shouldExtractIntent(String contextType) {
        Set<String> intentContexts = new Set<String>{
            'Onboarding', 'Coaching', 'CheckIn', 'Constraints'
        };
        return intentContexts.contains(contextType);
    }

    // Truncate message to fit field limits
    private String truncateMessage(String message) {
        if (String.isBlank(message)) return '';
        Integer maxLength = 130000;
        return message.length() > maxLength ? message.substring(0, maxLength) : message;
    }

    // Update contact last interaction timestamp
    private void updateContactTimestamp(String contactId, DateTime now) {
        try {
            Contact c = new Contact(Id = contactId);
            c.Last_Blakeney_Interaction__c = now;
            update c;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to update contact timestamp: ' + e.getMessage());
        }
    }

    // Insert error log for monitoring
    private void insertErrorLog(String source, String errorMsg, String stackTrace, String relatedId) {
        try {
            Schema.SObjectType errorLogType = Schema.getGlobalDescribe().get('Error_Log__c');
            if (errorLogType != null) {
                SObject log = errorLogType.newSObject();
                log.put('Source__c', source);
                log.put('Error_Message__c', errorMsg.length() > 32000 ? errorMsg.substring(0, 32000) : errorMsg);
                log.put('Stack_Trace__c', stackTrace.length() > 32000 ? stackTrace.substring(0, 32000) : stackTrace);
                log.put('Related_Record_Id__c', relatedId);
                log.put('Timestamp__c', DateTime.now());
                log.put('Severity__c', 'Error');
                insert log;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to log error: ' + e.getMessage());
        }
    }
}