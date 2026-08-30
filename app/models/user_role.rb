# frozen_string_literal: true

class UserRole < ApplicationRecord
  # Predefined role names are stored/queried in fixed English. They are always
  # resolved with locale: :en so lookups never depend on the request locale.
  validate :prevent_update, on: :update, if: :predefined?
  validates :name,
            presence: true,
            length: { minimum: Constants::NAME_MIN_LENGTH,
                      maximum: Constants::NAME_MAX_LENGTH },
            uniqueness: { case_sensitive: false }
  validates :permissions, presence: true, length: { minimum: 1 }
  validates :created_by, presence: true, unless: :predefined?
  validates :last_modified_by, presence: true, unless: :predefined?

  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :last_modified_by, class_name: 'User', optional: true
  has_many :user_assignments, dependent: :destroy
  has_many :user_group_assignments, dependent: :destroy
  has_many :team_assignments, dependent: :destroy

  scope :predefined, -> { where(predefined: true) }

  def self.owner_role
    new(
      name: I18n.t('user_roles.predefined.owner', locale: :en),
      permissions: PredefinedRoles::OWNER_PERMISSIONS,
      predefined: true
    )
  end

  def self.normal_user_role
    new(
      name: I18n.t('user_roles.predefined.normal_user', locale: :en),
      permissions: PredefinedRoles::NORMAL_USER_PERMISSIONS,
      predefined: true
    )
  end

  def self.technician_role
    new(
      name: I18n.t('user_roles.predefined.technician', locale: :en),
      permissions: PredefinedRoles::TECHNICIAN_PERMISSIONS,
      predefined: true
    )
  end

  def self.viewer_role
    new(
      name: I18n.t('user_roles.predefined.viewer', locale: :en),
      permissions: PredefinedRoles::VIEWER_PERMISSIONS,
      predefined: true
    )
  end

  def self.find_predefined_owner_role
    predefined.find_by(name: UserRole.public_send('owner_role').name)
  end

  def self.find_predefined_normal_user_role
    predefined.find_by(name: UserRole.public_send('normal_user_role').name)
  end

  def self.find_predefined_viewer_role
    predefined.find_by(name: UserRole.public_send('viewer_role').name)
  end

  def self.find_predefined_technician_role
    predefined.find_by(name: UserRole.public_send('technician_role').name)
  end

  PREDEFINED_I18N_KEYS = %w[owner normal_user technician viewer].freeze

  def display_name
    key = PREDEFINED_I18N_KEYS.find { |k| name == I18n.t("user_roles.predefined.#{k}", locale: :en) }
    key ? I18n.t("user_roles.predefined.#{key}") : name
  end

  def has_permission?(permission)
    permissions.include?(permission)
  end

  def owner?
    predefined? && name == I18n.t('user_roles.predefined.owner', locale: :en)
  end

  def viewer?
    predefined? && name == I18n.t('user_roles.predefined.viewer', locale: :en)
  end

  private

  def prevent_update
    errors.add(:base, I18n.t('user_roles.predefined.unchangable_error_message'))
  end
end
