# User management for the administrator (USR-01 ... USR-03).
class UsersController < ApplicationController
  before_action :set_user, only: %i[ edit update destroy ]

  def index
    authorize User
    @users = User.includes(:patrol_car).order(:name)
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
    fields = user_params
    fields = fields.except(:password) if fields[:password].blank?
    if @user.update(fields)
      redirect_to users_path, notice: "User updated"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @user.destroy!
    redirect_to users_path, notice: "User deleted", status: :see_other
  end

  private

  def set_user
    @user = authorize User.find(params.expect(:id))
  end

  def user_params
    params.expect(user: %i[ email_address name role patrol_car_id password active ])
  end
end
