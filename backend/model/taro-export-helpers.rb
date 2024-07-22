module ASpaceExport
  module ArchivalObjectDescriptionHelpers

    def controlaccess_linked_agents(include_unpublished = false)
      unless @controlaccess_linked_agents
        results = []
        linked = self.linked_agents || []
        linked.each_with_index do |link, i|
          if link['role'] == 'creator' || (link['_resolved']['publish'] == false && !include_unpublished)
            results << {}
            next
          end
          role = link['relator'] ? link['relator'] : (link['role'] == 'source' ? 'fmo' : nil)

          agent = link['_resolved'].dup
          sort_name = agent['display_name']['sort_name']
          rules = agent['display_name']['rules']
          source = agent['display_name']['source']
          authfilenumber = agent['display_name']['authority_id']
          content = sort_name.dup

          if link['terms'].length > 0
            content << " -- "
            content << link['terms'].map {|t| t['term']}.join(' -- ')
          end

          node_name = case agent['agent_type']
                      when 'agent_person'; 'persname'
                      when 'agent_family'; 'famname'
                      when 'agent_corporate_entity'; 'corpname'
                      when 'agent_software'; 'name'
                      end

          atts = {}
					atts[:role] = role if role
          atts[:source] = source if source
          atts[:rules] = rules if rules
          atts[:authfilenumber] = authfilenumber if authfilenumber
          atts[:audience] = 'internal' if link['_resolved']['publish'] == false
					atts[:encodinganalog] = case agent['agent_type']
												when 'agent_person'; '600'
												when 'agent_family'; '600'
												when 'agent_corporate_entity'; '610'
												when 'agent_software'; '630'
												end

          results << {:node_name => node_name, :atts => atts, :content => content}
        end

        @controlaccess_linked_agents = results
      end

      @controlaccess_linked_agents
    end


    def controlaccess_subjects
      unless @controlaccess_subjects
        results = []
        linked = self.subjects || []
        linked.each do |link|
          subject = link['_resolved']

          node_name = case subject['terms'][0]['term_type']
                      when 'function'; 'function'
                      when 'genre_form', 'style_period';  'genreform'
                      when 'geographic', 'cultural_context'; 'geogname'
                      when 'occupation'; 'occupation'
                      when 'topical'; 'subject'
                      when 'uniform_title'; 'title'
                      else; nil
                      end

          next unless node_name

          content = subject['terms'].map {|t| t['term']}.join(' -- ')

          atts = {}
          atts['source'] = subject['source'] if subject['source']
          atts['authfilenumber'] = subject['authority_id'] if subject['authority_id']
          atts['encodinganalog'] = case subject['terms'][0]['term_type']
                      when 'function'; '657'
                      when 'genre_form', 'style_period';  '655'
                      when 'geographic', 'cultural_context'; '651'
                      when 'occupation'; '656'
                      when 'topical'; '650'
                      when 'uniform_title'; '730'
                      end

          results << {:node_name => node_name, :atts => atts, :content => content}
        end

        @controlaccess_subjects = results
      end

      @controlaccess_subjects
    end

		def archdesc_dates
      unless @archdesc_dates
        results = []
        dates = self.dates || []
        dates.each do |date|
          normal = ""
          unless date['begin'].nil?
            normal = "#{date['begin']}/"
            normal_suffix = (date['date_type'] == 'single' || date['end'].nil? || date['end'] == date['begin']) ? date['begin'] : date['end']
            normal += normal_suffix ? normal_suffix : ""
          end
          type = ( date['date_type'] == 'inclusive' ) ? 'inclusive' : ( ( date['date_type'] == 'single') ? nil : 'bulk')
          content = if date['expression']
                      date['expression']
                    elsif date['end'].nil? || date['end'] == date['begin']
                      date['begin']
                    else
                      "#{date['begin']}-#{date['end']}"
                    end

          atts = {}
          atts[:type] = type if type
          atts[:certainty] = date['certainty'] if date['certainty']
          atts[:normal] = normal unless normal.empty?
          atts[:era] = date['era'].nil? ? 'ce' : date['era']
          atts[:calendar] = date['calendar'].nil? ? 'gregorian' : date['calendar']
          atts[:datechar] = date['label'] if date['label']
					atts[:encodinganalog] = date['date_type'] == 'bulk' ? '245$g' : '245$f'

          results << {:content => content, :atts => atts}
        end

        @archdesc_dates = results
      end

      @archdesc_dates
    end


	end
end
