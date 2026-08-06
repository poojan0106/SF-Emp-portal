/*
----------------------------------------------------------------------------
IntentSaveQueueable.cls
Creates or updates latest Career_Intent__c for candidate
----------------------------------------------------------------------------
*/
public class IntentSaveQueueable implements Queueable {

    private String contactId;
    private String sessionId;

    // Career Intent fields (4)
    private String shortTermGoal;
    private String mediumTermGoal;
    private String longTermGoal;
    private String aspirationalGoal;

    // Career Constraints fields (6)
    private String workLocation;
    private String remotePreference;
    private String minSalary;
    private String maxSalary;
    private String companySize;
    private String industryPreferences;

    // Constructor for complete career data
    public IntentSaveQueueable(String contactId, String sessionId,
                              String shortTermGoal, String mediumTermGoal,
                              String longTermGoal, String aspirationalGoal,
                              String workLocation, String remotePreference,
                              String minSalary, String maxSalary,
                              String companySize, String industryPreferences) {
        this.contactId = contactId;
        this.sessionId = sessionId;
        this.shortTermGoal = shortTermGoal;
        this.mediumTermGoal = mediumTermGoal;
        this.longTermGoal = longTermGoal;
        this.aspirationalGoal = aspirationalGoal;
        this.workLocation = workLocation;
        this.remotePreference = remotePreference;
        this.minSalary = minSalary;
        this.maxSalary = maxSalary;
        this.companySize = companySize;
        this.industryPreferences = industryPreferences;
    }

    // Legacy constructor for partial intent updates
    public IntentSaveQueueable(String contactId, String shortTermGoal, String mediumTermGoal,
                              String longTermGoal, String aspirationalGoal) {
        this.contactId = contactId;
        this.shortTermGoal = shortTermGoal;
        this.mediumTermGoal = mediumTermGoal;
        this.longTermGoal = longTermGoal;
        this.aspirationalGoal = aspirationalGoal;
    }

    public void execute(QueueableContext qc) {
        Savepoint sp = Database.setSavepoint();

        try {
            lockCandidateContact(contactId);
            Career_Intent__c intent = getLatestIntent(contactId);
            Boolean isNew = intent == null;
            if (isNew) {
                intent = new Career_Intent__c();
            }

            intent.Contact__c = contactId;
            intent.Candidate__c = contactId;
            if (String.isNotBlank(sessionId)) {
                intent.Session_ID__c = sessionId;
            }
            intent.Last_Check_In__c = DateTime.now();

            // Career Intent fields (from conversation answers)
            if (String.isNotBlank(shortTermGoal)) {
                intent.Short_Term_Goal__c = shortTermGoal;
            }
            if (String.isNotBlank(mediumTermGoal)) {
                intent.Medium_Term_Goal__c = mediumTermGoal;
            }
            if (String.isNotBlank(longTermGoal)) {
                intent.Long_Term_Goal__c = longTermGoal;
            }
            if (String.isNotBlank(aspirationalGoal)) {
                intent.Aspirational_Goal__c = aspirationalGoal;
            }

            // Career Constraints fields (from conversation answers)
            if (String.isNotBlank(workLocation)) {
                intent.Willing_to_Relocate__c = workLocation;
            }
            if (String.isNotBlank(remotePreference)) {
                intent.Short_Term_Remote__c = remotePreference;
            }
            if (String.isNotBlank(minSalary)) {
                intent.Min_Salary_Expactation__c = normalizeSalary(minSalary);
            }
            if (String.isNotBlank(maxSalary)) {
                intent.Max_Salary_Expactation__c = normalizeSalary(maxSalary);
            }
            if (String.isNotBlank(companySize)) {
                intent.Short_Term_Company_Size__c = companySize;
            }
            if (String.isNotBlank(industryPreferences)) {
                intent.Industry_Preferences__c = industryPreferences;
            }
            String contactSkills = normalizeSkillText(getContactSkills(contactId));
            if (String.isNotBlank(contactSkills)) {
                intent.Skills__c = contactSkills;
            }

            if (isNew) {
                insert intent;
            } else {
                update intent;
            }

            syncContactSalary(contactId, intent.Min_Salary_Expactation__c, intent.Max_Salary_Expactation__c);
            CareerPathwaySyncService.syncForIntent(intent.Id);
            BlakeneyInteractionEventService.publish(
                parseId(contactId),
                isNew ? 'Onboarding' : 'Goal Update',
                'Career_Intent__c goals/preferences/skills/salary',
                intent.Id,
                null,
                sessionId
            );

            System.debug((isNew ? 'Created' : 'Updated') + ' Career Intent record: ' + intent.Id);

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, 'IntentSaveQueueable Error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
        }
    }

    private Career_Intent__c getLatestIntent(String contactId) {
        if (String.isBlank(contactId)) {
            return null;
        }

        List<Career_Intent__c> intents = [
            SELECT Id, Contact__c, Candidate__c, Session_ID__c,
                   Short_Term_Goal__c, Medium_Term_Goal__c, Long_Term_Goal__c,
                   Aspirational_Goal__c, Willing_to_Relocate__c, Short_Term_Remote__c,
                   Min_Salary_Expactation__c, Max_Salary_Expactation__c,
                   Short_Term_Company_Size__c, Industry_Preferences__c, Skills__c
            FROM Career_Intent__c
            WHERE Contact__c = :contactId OR Candidate__c = :contactId
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        return intents.isEmpty() ? null : intents[0];
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

    private void syncContactSalary(String contactId, Decimal minSalaryValue, Decimal maxSalaryValue) {
        if (String.isBlank(contactId) || (minSalaryValue == null && maxSalaryValue == null)) {
            return;
        }

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
    }

    private String getContactSkills(String contactId) {
        if (String.isBlank(contactId)) return null;
        try {
            List<Contact> contacts = [
                SELECT R_ATS__Skills__c
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
            ];
            return contacts.isEmpty() ? null : contacts[0].R_ATS__Skills__c;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Unable to read Contact skills for intent sync: ' + e.getMessage());
            return null;
        }
    }

    private String normalizeSkillText(String incomingSkills) {
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

    private Id parseId(String value) {
        if (String.isBlank(value)) return null;
        try {
            return (Id) value;
        } catch (Exception e) {
            return null;
        }
    }

    // Normalize salary input
    private Integer normalizeSalary(String input) {
        if (String.isBlank(input)) {
            return null;
        }

        // Remove $ and commas
        String cleaned = input.replace('$', '').replace(',', '').trim();

        try {
            return Integer.valueOf(cleaned);
        } catch (Exception e) {
            return null;
        }
    }
}