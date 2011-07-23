# data-vocabulary `Person` snippet:
module RDF::Linter
  {
    "http://rdf.data-vocabulary.org/#Review" => "http://rdf.data-vocabulary.org/#",
    "http://data-vocabulary.org/Review" => "http://www.w3.org/1999/xhtml/microdata#http://data-vocabulary.org/Review%23:",
    "http://rdf.data-vocabulary.org/#Review-aggregate" => "http://rdf.data-vocabulary.org/#",
    "http://data-vocabulary.org/Review-aggregate" => "http://www.w3.org/1999/xhtml/microdata#http://data-vocabulary.org/Review-aggregate%23:",
  }.each do |type, prefix|
    LINTER_HAML.merge!({
      RDF::URI(type) => {
        # Properties to be used in snippet title
        :title_props => ["#{prefix}itemreviewed", "#{prefix}addr"],
        # Post-processing on nested markup
        :title_fmt => lambda {|list, &block| list.map{|e| block.call(e)}.compact.join("- ")},
        # Properties to be used in snippet photo
        :photo_props => ["#{prefix}image"],
        # Properties to be used in snippet body
        :body_props => [
          "#{prefix}rating",
          "#{prefix}count",
        ],
        # Post-processing on nested markup
        :body_fmt => lambda {|list, &block|
          rating = block.call("#{prefix}rating")
          count = block.call("#{prefix}count")
          rating.to_s + (count ? "#{count} reviews" : "")
        },
        :description_props => ["#{prefix}summary"],
        # Properties to be used when snippet is nested
        :nested_props => [
          "#{prefix}rating",
          "#{prefix}count",
        ],
        :nested_fmt => lambda {|list, &block| list.map{|e| block.call(e)}.join("") + "reviews"},
        :property_value => %(
          - if predicate.to_s.match('#{prefix.gsub('#', '\#')}rating')
            != rating_helper(predicate, object)
          - elsif object.node? && res = yield(object)
            != res
          - elsif ["#{prefix}image", "#{prefix}photo"].include?(predicate)
            %span{:rel => rel}
              %img{:src => object.to_s, :alt => ""}
          - elsif object.literal?
            %span{:property => property, :content => get_content(object), :lang => get_lang(object), :datatype => get_dt_curie(object)}= escape_entities(get_value(object))
          - else
            %span{:rel => rel, :resource => get_curie(object)}
        ),
      }
    })
  end
end