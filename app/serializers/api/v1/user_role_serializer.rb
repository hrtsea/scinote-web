# frozen_string_literal: true

module Api
  module V1
    class UserRoleSerializer < ActiveModel::Serializer
      attributes :id, :name, :permissions, :display_name

      def display_name
        object.display_name
      end
    end
  end
end
