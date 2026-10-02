module Api
  module V1
    # API-01, API-02: the guarded sites, with the search, filters and order
    # of the site list (FLT-04, FLT-05, SRT-02).
    class SitesController < BaseController
      def index
        authorize GuardedSite
        @sites = GuardedSite.list(text: params[:q].to_s,
                                  filters: params.permit(:site_type, :district, :contract_status),
                                  sort: params[:sort], direction: params[:direction])
      end

      def show
        @site = authorize GuardedSite.includes(:address).find(params.expect(:id))
      end

      # API-03
      def create
        @site = authorize GuardedSite.new(fields)
        @site.save ? render(:show, status: :created) : invalid(@site)
      end

      # API-04
      def update
        @site = authorize GuardedSite.find(params.expect(:id))
        @site.update(fields) ? render(:show) : invalid(@site)
      end

      # API-05: a site with calls stays (BR-9).
      def destroy
        site = authorize GuardedSite.find(params.expect(:id))
        site.destroy ? head(:no_content) : refuse(site.kept_reason)
      end

      private

      def fields = params.permit(*::GuardedSitesController::FIELDS)
    end
  end
end
