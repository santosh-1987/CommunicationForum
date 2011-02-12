class Group
  include Mongoid::Document
  include Mongoid::Timestamps

  include MongoidExt::Slugizer
  include MongoidExt::Storage
  include MongoidExt::Filter

  include Shapado::Models::CustomHtmlMethods

  BLACKLIST_GROUP_NAME = ["www", "net", "org", "admin", "ftp", "mail", "test", "blog",
                 "bug", "bugs", "dev", "ftp", "forum", "community", "mail", "email",
                 "webmail", "pop", "pop3", "imap", "smtp", "stage", "stats", "status",
                 "support", "survey", "download", "downloads", "faqs", "wiki",
                 "assets1", "assets2", "assets3", "assets4", "staging", "code"]

  identity :type => String

  field :name, :type => String
  field :subdomain, :type => String
  field :domain, :type => String
  index :domain
  field :legend, :type => String
  field :description, :type => String
  field :default_tags, :type => Array, :default => []
  field :has_custom_ads, :type => Boolean, :default => true
  field :state, :type => String, :default => "pending" #pending, active, closed
  field :isolate, :type => Boolean, :default => false
  field :private, :type => Boolean, :default => false
  field :theme, :type => String, :default => "plain"
  field :owner_id, :type => String
  field :analytics_id, :type => String
  field :analytics_vendor, :type => String
  field :has_custom_analytics, :type => Boolean, :default => true

  field :language, :type => String
  field :languages, :type => Set
  index :languages

  field :activity_rate, :type => Float, :default => 0.0
  field :openid_only, :type => Boolean, :default => false
  field :registered_only, :type => Boolean, :default => false
  field :has_adult_content, :type => Boolean, :default => false

  field :wysiwyg_editor, :type => Boolean, :default => false

  field :has_reputation_constrains, :type => Boolean, :default => true
  field :reputation_rewards, :type => Hash, :default => REPUTATION_REWARDS
  field :reputation_constrains, :type => Hash, :default => REPUTATION_CONSTRAINS
  field :forum, :type => Boolean, :default => false

  field :custom_html, :type => CustomHtml, :default => CustomHtml.new
  field :has_custom_html, :type => Boolean, :default => true
  field :has_custom_js, :type => Boolean, :default => true
  field :fb_button, :type => Boolean, :default => true

  field :enable_latex, :type => Boolean, :default => false


  field :logo_info, :type => Hash, :default => {"width" => 215, "height" => 60}
  field :share, :type => Share, :default => Share.new

  field :notification_opts, :type => GroupNotificationConfig

  field :twitter_account, :type => Hash, :default => { }

  file_key :logo, :max_length => 2.megabytes
  file_key :custom_css, :max_length => 256.kilobytes
  file_key :custom_favicon, :max_length => 256.kilobytes

  slug_key :name, :unique => true
  filterable_keys :name

  references_many :ads, :dependent => :destroy
  references_many :tags, :dependent => :destroy

  embeds_many :welcome_widgets, :class_name => "Widget"
  embeds_many :mainlist_widgets, :class_name => "Widget"
  embeds_many :question_widgets, :class_name => "Widget"
  embeds_many :external_widgets, :class_name => "Widget"

  references_many :badges, :dependent => :destroy
  references_many :questions, :dependent => :destroy
  references_many :answers, :dependent => :destroy
#   references_many :votes, :dependent => :destroy # FIXME:
  references_many :pages, :dependent => :destroy
  references_many :announcements, :dependent => :destroy
  references_many :constrains_configs, :dependent => :destroy

  referenced_in :owner, :class_name => "User"
  embeds_many :comments

  validates_presence_of     :owner
  validates_presence_of     :name

  validates_length_of       :name,           :in => 3..40
  validates_length_of       :description,    :in => 3..10000, :allow_blank => true
  validates_length_of       :legend,         :maximum => 50
  validates_length_of       :default_tags,   :in => 0..15,
      :message =>  I18n.t('activerecord.models.default_tags_message')
  validates_uniqueness_of   :name
  validates_uniqueness_of   :subdomain
  validates_presence_of     :subdomain
  validates_format_of       :subdomain, :with => /^[a-z0-9\-]+$/i
  validates_length_of       :subdomain, :in => 3..32

  validates_inclusion_of :language, :in => AVAILABLE_LANGUAGES, :allow_blank => true
  #validates_inclusion_of :theme, :in => AVAILABLE_THEMES

  validate :set_subdomain, :on => :create
  validate :check_domain, :on => :create

  validate :check_reputation_configs

  validates_exclusion_of      :subdomain,
                              :in => BLACKLIST_GROUP_NAME,
                              :message => "Sorry, this group subdomain is reserved by"+
                                          " our system, please choose another one"

  before_save :disallow_javascript
  before_save :modify_attributes

  # TODO: store this variable
  def has_custom_domain?
    @has_custom_domain ||= self[:domain].to_s !~ /#{AppConfig.domain}/
  end

  def tag_list
    TagList.where(:group_id => self.id).first || TagList.create(:group_id => self.id)
  end

  def default_tags=(c)
    if c.kind_of?(String)
      c = c.downcase.split(",").join(" ").split(" ")
    end
    self[:default_tags] = c
  end
  alias :user :owner

  def add_member(user, role)
    membership = user.config_for(self.id, true)
    if membership.reputation < 5
      membership.reputation = 5
    end
    membership.role = role

    user.save
  end

  def is_member?(user)
    user.member_of?(self)
  end

  def users(conditions = {})
    conditions.merge!("membership_list.#{self.id}.reputation" => {:$exists => true})

    unless conditions[:near]
      User.where(conditions)
    else
      point = options.delete(:near)
      User.near(point, {}).where(conditions)
    end
  end
  alias_method :members, :users

  def owners
    users({ "membership_list.#{self.id}.role" => 'owner' })
  end

  def mods
    users({ "membership_list.#{self.id}.role" => 'moderator' })
  end
  alias_method :moderators, :mods

  def mods_owners
    users({ "membership_list.#{self.id}.role" => {:$in => ['moderator', 'owner']} })
  end

  def pending?
    state == "pending"
  end

  def on_activity(action)
    value = 0
    case action
      when :ask_question
        value = 0.1
      when :answer_question
        value = 0.3
    end
    self.increment(:activity_rate => value)
  end

  def language=(lang)
    if lang != "none"
      self[:language] = lang
    else
      self[:language] = nil
    end
  end

  def self.humanize_reputation_constrain(key)
    I18n.t("groups.shared.reputation_constrains.#{key}", :default => key.humanize)
  end

  def self.humanize_reputation_rewards(key)
    I18n.t("groups.shared.reputation_rewards.#{key}", :default => key.humanize)
  end

  def self.find_file_from_params(params, request)
    if request.path =~ /\/(logo|css|favicon)\/([^\/\.?]+)/
      @group = Group.find($2)
      case $1
      when "logo"
        @group.logo
      when "css"
        if @group.has_custom_css?
          css=@group.custom_css
          css.content_type = "text/css"
          css
        end
      when "favicon"
        @group.custom_favicon if @group.has_custom_favicon?
      end
    end
  end

  def reset_twitter_account
    self.twitter_account = { }
    self.save!
  end

  def update_twitter_account_with_oauth_token(token, secret, screen_name)
    self.twitter_account = self.twitter_account ? self.twitter_account : { }
    self.twitter_account["token"] = token
    self.twitter_account["secret"] = secret
    self.twitter_account["screen_name"] = screen_name
    self.save!
  end

  def has_twitter_oauth?
    self.twitter_account && self.twitter_account["token"] && self.twitter_account["secret"]
  end

  def twitter_client
      if self.has_twitter_oauth? && (config = Multiauth.providers["Twitter"])
        TwitterOAuth::Client.new(
          :consumer_key => config["id"],
          :consumer_secret => config["token"],
          :token => self.twitter_account["token"],
          :secret => self.twitter_account["secret"]
        )
      end
  end
  protected
  #validations
  def set_subdomain
    self["subdomain"] = self["slug"]
  end

  def check_domain
    if domain.blank?
      self[:domain] = "#{subdomain}.#{AppConfig.domain}"
    end
  end

  def check_reputation_configs
    if self.reputation_constrains_changed?
      self.reputation_constrains.each do |k,v|
        self.reputation_constrains[k] = v.to_i
        if !REPUTATION_CONSTRAINS.has_key?(k)
          self.errors.add(:reputation_constrains, "Invalid key")
          return false
        end
      end
    end

    if self.reputation_rewards_changed?
      valid = true
      [["vote_up_question", "undo_vote_up_question"],
       ["vote_down_question", "undo_vote_down_question"],
       ["question_receives_up_vote", "question_undo_up_vote"],
       ["question_receives_down_vote", "question_undo_down_vote"],
       ["vote_up_answer", "undo_vote_up_answer"],
       ["vote_down_answer", "undo_vote_down_answer"],
       ["answer_receives_up_vote", "answer_undo_up_vote"],
       ["answer_receives_down_vote", "answer_undo_down_vote"],
       ["answer_picked_as_solution", "answer_unpicked_as_solution"]].each do |action, undo|
        if self.reputation_rewards[action].to_i > (self.reputation_rewards[undo].to_i*-1)
          valid = false
          self.errors.add(undo, "should be less than #{(self.reputation_rewards[action].to_i)*-1}")
        end
      end
      return false unless valid

      self.reputation_rewards.each do |k,v|
        self.reputation_rewards[k] = v.to_i
        if !REPUTATION_REWARDS.has_key?(k)
          self.errors.add(:reputation_rewards, "Invalid key")
          return false
        end
      end
    end

    return true
  end

  #callbacks
  def modify_attributes
    self.domain.downcase!
    self.subdomain.downcase!
    self.languages << self.language
  end

  def disallow_javascript
    unless self.has_custom_js
       %w[footer _head _question_help _question_prompt head_tag].each do |key|
         value = self.custom_html[key]
         if value.kind_of?(Hash)
           value.each do |k,v|
             value[k] = v.to_s.gsub(/<*.?script.*?>/, "")
           end
         elsif value.kind_of?(String)
           value = value.gsub(/<*.?script.*?>/, "")
         end
         self.custom_html[key] = value
       end
    end
  end
end
