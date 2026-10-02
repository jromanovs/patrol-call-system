module Api
  module V1
    # API-01, API-02: the guarded sites, with the search, filters and order
    # of the site list (FLT-04, FLT-05, SRT-02).
    class SitesController < BaseController
      def index
        authorize GuardedSite
        @sites = GuardedSite.list(text: params[:q].to_s, filters: params.permit(:site_type, :district, :contract_status),
                                  sort: params[:sort], direction: params[:direction])
      end

      def show
        @site = authorize GuardedSite.includes(:address).find(params.expect(:id))
      end
    end
  end
end
