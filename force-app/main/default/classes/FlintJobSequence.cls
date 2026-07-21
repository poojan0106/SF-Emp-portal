// ============================================================================
// 2. FLINT JOB SEQUENCE - Question array (source of truth)
// ============================================================================
public class FlintJobSequence {
    
    public static final List<String> JOB_INTAKE_QUESTIONS = new List<String>{
        'Hi! I\'m Flint, your AI recruitment consultant. I\'m here to help you create a compelling job posting. Tell me about the role you\'re hiring for.',
        'What\'s the seniority level (Junior, Mid, Senior, Lead, Executive)?',
        'What are the must-have skills for this role?',
        'What nice-to-have skills would be a bonus?',
        'What\'s the salary range? I can provide market recommendations.',
        'What\'s your timeline? How urgent is this hire?',      //Test
        'Is this a permanent, contract, or temporary position?',
        'Tell me about your team culture and what kind of fit you\'re looking for.',
         'What\'s your location?'
    };
    
    public static final Map<Integer, String> INPUT_TYPES = new Map<Integer, String>{
        0 => 'text',
        1 => 'text',
        2 => 'text',
        3 => 'text',
        4 => 'number',
        5 => 'text',
        6 => 'text',
        7 => 'text',
        8 => 'text'
            
    };
    
    public static final Map<Integer, List<String>> QUICK_REPLIES = new Map<Integer, List<String>>{
        0 => new List<String>(),
        1 => new List<String>{ 'Junior', 'Mid-Level', 'Senior', 'Lead', 'Executive' },
        2 => new List<String>(),
        3 => new List<String>(),
        4 => new List<String>{ '$60K-$90K', '$90K-$120K', '$120K-$150K', '$150K+' },
        5 => new List<String>{ 'Immediate (0-2 weeks)', 'Moderate (2-4 weeks)', 'Flexible (1+ month)' },
        6 => new List<String>{ 'Permanent', 'Contract', 'Temporary' },
        7 => new List<String>(),
        8 => new List<String>()
    };
    
    public static String getQuestion(Integer questionNum) {
        if (questionNum >= 0 && questionNum < JOB_INTAKE_QUESTIONS.size()) {
            return JOB_INTAKE_QUESTIONS[questionNum];
        }
        return 'Congratulations! Your job posting is complete. You can now publish it.';
    }
    
    public static String getInputType(Integer questionNum) {
        return INPUT_TYPES.containsKey(questionNum) ? INPUT_TYPES.get(questionNum) : 'text';
    }
    
    public static List<String> getQuickReplies(Integer questionNum) {
        return QUICK_REPLIES.containsKey(questionNum) ? QUICK_REPLIES.get(questionNum) : new List<String>();
    }
    
    public static Boolean isComplete(Integer questionNum) {
        return questionNum >= JOB_INTAKE_QUESTIONS.size();
    }
}