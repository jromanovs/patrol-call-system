# USR-04: every signed-in user issues their own API key. It is shown once,
# right after it is issued; afterwards only its digest is known.
class ApiKeysController < ApplicationController
  def show; end

  def create
    @key = Current.user.issue_api_key
    render :show, status: :created
  end
end
