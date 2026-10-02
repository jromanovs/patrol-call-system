# Guarded sites (2.2): the list with search, filters and sorting, the site
# page, adding, editing and deleting.
class GuardedSitesController < ApplicationController
  FIELDS = %i[ contract_number name client_name address_id site_type district keyholder_phone contract_status
               contract_start_date access_notes ].freeze

  before_action :set_site, only: %i[ show edit update destroy ]

  def index
    authorize GuardedSite
    @text = params[:q].to_s
    @sites = GuardedSite.list(text: @text, filters: params.permit(:site_type, :district, :contract_status),
                              sort: params[:sort], direction: params[:direction])
  end

  def show
    @calls = @site.calls.order(received_at: :desc)
    @map = MapBuild.new.current
    @marker = MapMarker.for([ @site ]).first if @map
  end

  def new
    @site = authorize GuardedSite.new
  end

  def edit; end

  def create
    @site = authorize GuardedSite.new(site_params)
    if @site.save
      redirect_to @site, notice: "Site created"
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @site.update(site_params)
      redirect_to @site, notice: "Site updated"
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DEL-01, DEL-02: a site with calls stays (BR-9).
  def destroy
    if @site.destroy
      redirect_to guarded_sites_path, notice: "Site deleted", status: :see_other
    else
      redirect_to @site, status: :see_other, alert: @site.kept_reason
    end
  end

  private

  def default_sort = "name"
  helper_method :default_sort

  def set_site
    @site = authorize GuardedSite.find(params.expect(:id))
  end

  def site_params = params.expect(guarded_site: FIELDS)
end
