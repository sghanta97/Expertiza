# This is a new model create by E1577 (heat map)
# represents each table in the view_team view.
# the important piece to note is that the @listofrows is a  list of type VmQuestionResponse_Row, which represents a row of the heatgrid table.
class VmQuestionResponse
  @questionnaire = nil
  @assignment = nil

  def initialize(questionnaire, assignment = nil, round = nil)
    @assignment = assignment
    @questionnaire = questionnaire
    if questionnaire.type == "ReviewQuestionnaire"
      @round = round ? round : AssignmentQuestionnaire.find_by(assignment_id: @assignment.id, questionnaire_id: questionnaire.id).used_in_round
    end

    @rounds = @assignment.rounds_of_reviews

    @list_of_rows = []
    @list_of_reviewers = []
    @list_of_reviews = []
    @list_of_team_participants = []
    @max_score = questionnaire.max_question_score
    @questionnaire_type = questionnaire.type
    @questionnaire_display_type = questionnaire.display_type
    @rounds = rounds
    @round = round
    @name  = questionnaire.name
  end

  attr_reader :name

  def add_questions(questions)
    questions.each do |question|
      # Get the maximum score for this question. For some unknown, godforsaken reason, the max
      # score for the question is stored not on the question, but on the questionnaire. Neat.
      corresponding_questionnaire = Questionnaire.find_by(id: question.questionnaire.id)
      question_max_score = corresponding_questionnaire.max_question_score
      # if this question is a header (table header, section header, column header), ignore this question
      unless question.is_a? QuestionnaireHeader
        row = VmQuestionResponseRow.new(question.txt, question.id, question.weight, question_max_score, question.seq)
        @list_of_rows << row
      end
    end
  end

  def add_reviews(participant, team, vary, current_role_name)
    if @questionnaire_type == "ReviewQuestionnaire"
      reviews = if vary
                  ReviewResponseMap.get_responses_for_team_round(team, @round)
                else
                  ReviewResponseMap.get_assessments_for(team)
                end
      # variable to store self review
      @store_needed_self_review = nil
      # find and selected self reviewers based on current user role
      self_reviews = SelfReviewResponseMap.get_assessments_for(team) # Get all Self Reviews for the team
      self_reviews.each do |review|
        self_review_mapping = SelfReviewResponseMap.find(review.map_id) # Find respons maps baed on map id
        if self_review_mapping && self_review_mapping.present?
          # if the current role is not student fetch all self reviewers i.e instructor view
          if !current_role_name.eql? "Student"
            @list_of_reviewers << participant
          end
          # if it is a student view show only that particular students self review
          if participant.id == self_review_mapping.reviewer_id
            participant = Participant.find(self_review_mapping.reviewer_id)
            @list_of_reviewers << participant
            @store_needed_self_review = review
          end
        end
      end
      # Find and add all peer reviewers
      reviews.each do |review|
        review_mapping = ReviewResponseMap.find(review.map_id)
        if review_mapping && review_mapping.present?
          participant = Participant.find(review_mapping.reviewer_id)
          @list_of_reviewers << participant
        end
      end
      # Add all reviews i.e self  + peer , based on the role and type of assignment
      if !@store_needed_self_review.nil? and current_role_name.eql? "Student"
        @list_of_reviews = reviews + [@store_needed_self_review]
      elsif !@store_needed_self_review.nil?
        @list_of_reviews = reviews + self_reviews
      else
        @list_of_reviews = reviews
      end
    elsif @questionnaire_type == "AuthorFeedbackQuestionnaire"
      reviews = participant.feedback # feedback reviews
      reviews.each do |review|
        review_mapping = FeedbackResponseMap.where(id: review.map_id).first
        participant = Participant.find(review_mapping.reviewer_id)
        @list_of_reviewers << participant
        @list_of_reviews << review
      end
    elsif @questionnaire_type == "TeammateReviewQuestionnaire"
      reviews = participant.teammate_reviews
      reviews.each do |review|
        review_mapping = TeammateReviewResponseMap.where(id: review.map_id).first
        participant = Participant.find(review_mapping.reviewer_id)
        # commenting out teamreviews. I just realized that teammate reviews are hidden during the current semester,
        # and I don't know how to implement the logic, so I'm being safe.
        @list_of_reviewers << participant
        @list_of_reviews << review
      end
    elsif @questionnaire_type == "MetareviewQuestionnaire"
      reviews = participant.metareviews
      reviews.each do |review|
        review_mapping = MetareviewResponseMap.where(id: review.map_id).first
        participant = Participant.find(review_mapping.reviewer_id)
        @list_of_reviewers << participant
        @list_of_reviews << review
      end
    end

    reviews.each do |review|
      answers = Answer.where(response_id: review.response_id)
      answers.each do |answer|
        add_answer(answer)
      end
    end
    # Find all answers based on user role
    if current_role_name != "Student" and !@store_needed_self_review.nil?
      answers = Answer.where(response_id: self_reviews.each {|self_review| self_review.response_id})
      answers.each do |answer|
        add_answer(answer)
      end
    elsif !@store_needed_self_review.nil?
      answers = Answer.where(response_id: @store_needed_self_review.response_id)
      answers.each do |answer|
        add_answer(answer)
      end
    end
  end

  def display_team_members
    @output = ""
    if @questionnaire_type == "MetareviewQuestionnaire" || @questionnaire_type == "ReviewQuestionnaire"
      @output = "Team members:"
      @list_of_team_participants.each do |participant|
        @output = @output + " (" + participant.fullname + ") "
      end

    end

    @output
  end

  def add_team_members(team)
    @list_of_team_participants = team.participants
  end

  def listofteamparticipants
    @list_of_team_participants
  end

  attr_reader :max_score

  def max_score_for_questionnaire
    @max_score * @list_of_rows.length
  end

  def max_score_for_questionnaire
    @max_score * @list_of_rows.length
  end

  attr_reader :rounds

  attr_reader :round

  attr_reader :questionnaire_type

  attr_reader :questionnaire_display_type

  attr_reader :list_of_reviews

  attr_reader :list_of_rows

  attr_reader :list_of_reviewers

  def add_answer(answer)
    # We want to add each response score from this review (answer) to its corresponding
    # question row.
    @list_of_rows.each do |row|
      next unless row.question_id == answer.question_id
      # Go ahead and calculate what the color code for this score should be.
      question_max_score = row.question_max_score

      # This calculation is a little tricky. We're going to find the percentage for this score,
      # multiply it by 5, and then take the ceiling of that value to get the color code. This
      # should work for any point value except 0 (which we'll handle separately).
      color_code_number = 0
      if answer.answer.is_a? Numeric
        color_code_number = ((answer.answer.to_f / question_max_score.to_f) * 5.0).ceil
        # Color code c0 is reserved for null spaces in the table which will be gray.
        color_code_number = 1 if color_code_number == 0
      end

      # Find out the tag prompts assosiated with the question
      tag_deps = TagPromptDeployment.where(questionnaire_id: @questionnaire.id, assignment_id: @assignment.id)
      vm_tag_prompts = []

      question = Question.find(answer.question_id)

      # check if the tag prompt applies for thsi question type and if the comment length is above the threshold
      # if it does, then associate this answer with the tag_prompt and tag deployment (the setting)
      tag_deps.each do |tag_dep|
        if tag_dep.question_type == question.type and answer.comments.length > tag_dep.answer_length_threshold
          vm_tag_prompts.append(VmTagPromptAnswer.new(answer, TagPrompt.find(tag_dep.tag_prompt_id), tag_dep))
        end
      end
      # end tag_prompt code

      # Now construct the color code and we're good to go!
      color_code = "c#{color_code_number}"
      row.score_row.push(VmQuestionResponseScoreCell.new(answer.answer, color_code, answer.comments, vm_tag_prompts))
    end
  end

  def get_number_of_comments_greater_than_10_words
    first_time = true

    @list_of_reviews.each do |review|
      answers = Answer.where(response_id: review.response_id)
      answers.each do |answer|
        @list_of_rows.each do |row|
          row.countofcomments = row.countofcomments + 1 if row.question_id == answer.question_id && answer.comments && answer.comments.split.size > 10
        end
      end
    end
  end
end
