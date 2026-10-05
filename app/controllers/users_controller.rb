# User management for the administrator (USR-01 ... USR-03).
class UsersController < ApplicationController
  before_action :set_user, only: %i[ edit update destroy ]

  def index
    authorize User
    @users = User.includes(:patrol_car, :avatar_attachment).order(:name)
  end

  def new
    @user = authorize User.new
  end

  def create
    @user = authorize User.new(user_params)
    if @user.save
      redirect_to users_path, notice: "User created"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  # An empty password keeps the current one; an empty car is a choice (USR-02).
  def update
    # USR-08: a password is not a field of this form; it has a dialog of its own.
    if @user.update(user_params.except(:password))
      redirect_to users_path, notice: "User updated"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @user.destroy
      redirect_to users_path, notice: "User deleted", status: :see_other
    else
      redirect_to users_path, alert: @user.kept_reason, status: :see_other
    end
  end

  private

  def set_user
    @user = authorize User.find(params.expect(:id))
  end

  def user_params
    params.expect(user: %i[ email_address name role patrol_car_id password active ])
  end
end
