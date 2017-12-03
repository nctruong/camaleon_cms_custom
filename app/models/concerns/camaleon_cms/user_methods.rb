class CamaleonCms::UniqValidatorUser < ActiveModel::Validator
  def validate(record)
    users = CamaleonCms::User.all
    users = CamaleonCms::User.where(site_id: record.site_id) unless PluginRoutes.system_info["users_share_sites"]
    record.errors[:base] << "#{I18n.t('camaleon_cms.admin.users.message.requires_different_username')}" if users.where(username: record.username).where.not(id: record.id).size > 0
    record.errors[:base] << "#{I18n.t('camaleon_cms.admin.users.message.requires_different_email')}" if users.where(email: record.email).where.not(id: record.id).size > 0
  end
end

module CamaleonCms::UserMethods extend ActiveSupport::Concern
  included do
    include CamaleonCms::Metas
    include CamaleonCms::CustomFieldsRead

    validates_with CamaleonCms::UniqValidatorUser

    before_create { generate_token(:auth_token) }
    before_save :before_saved
    before_create :before_saved
    before_destroy :reassign_posts
    # relations

    has_many :metas, ->{ where(object_class: 'User')}, :class_name => "CamaleonCms::Meta", foreign_key: :objectid, dependent: :destroy
    has_many :user_relationships, class_name: "CamaleonCms::UserRelationship", foreign_key: :user_id, dependent: :destroy#,  inverse_of: :user
    has_many :term_taxonomies, foreign_key: :term_taxonomy_id, class_name: "CamaleonCms::TermTaxonomy", through: :user_relationships, :source => :term_taxonomies
    has_many :all_posts, class_name: "CamaleonCms::Post"

    #scopes
    scope :admin_scope, -> { where(:role => 'admin') }
    scope :actives, -> { where(:active => 1) }
    scope :not_actives, -> { where(:active => 0) }

    #vars
    STATUS = {0 => 'Active', 1=>'Not Active'}
    ROLE = { 'admin'=>'Administrator', 'client' => 'Client'}
  end

  # return all posts of this user on site
  def posts(site)
    site.posts.where(user_id: self.id)
  end

  def fullname
    "#{self.first_name} #{self.last_name}".titleize
  end

  def admin?
    role == 'admin'
  end

  def client?
    self.role == 'client'
  end

  # return the UserRole Object of this user in Site
  def get_role(site)
    @_user_role ||= site.user_roles.where(slug: self.role).first
  end

  # assign a new site for current user
  def assign_site(site)
    self.update_column(:site_id, site.id)
  end

  def sites
    if PluginRoutes.system_info["users_share_sites"]
      CamaleonCms::Site.all
    else
      CamaleonCms::Site.where(id: self.site_id)
    end
  end

  # DEPRECATED, please use user.the_role
  def roleText
    User::ROLE[self.role]
  end

  def created
    self.created_at.strftime('%d/%m/%Y %H:%M')
  end

  def updated
    self.updated_at.strftime('%d/%m/%Y %H:%M')
  end

  # auth
  def generate_token(column)
    begin
      self[column] = SecureRandom.urlsafe_base64
    end while CamaleonCms::User.exists?(column => self[column])
  end

  def send_password_reset
    generate_token(:password_reset_token)
    self.password_reset_sent_at = Time.zone.now
    save!
  end

  def send_confirm_email
    generate_token(:confirm_email_token)
    self.confirm_email_sent_at = Time.zone.now
    save!
  end

  def decorator_class
    'CamaleonCms::UserDecorator'.constantize
  end

  private
  def before_saved
    self.role = PluginRoutes.system_info["default_user_role"] if self.role.blank?
  end

  # deprecated
  def set_all_sites
    return
  end

  # reassign all posts of this user to first admin
  # reassign all comments of this user to first admin
  # if doesn't exist any other administrator, this will cancel the user destroy
  def reassign_posts
    all_posts.each do |p|
      s = p.post_type.site
      u = s.users.admin_scope.where.not(id: self.id).first
      if u.present?
        p.update_column(:user_id, u.id)
        p.comments.where(user_id: self.id).each do |c|
          c.update_column(:user_id, u.id)
        end
      end
    end
  end
end