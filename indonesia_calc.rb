require 'set'

class Game
    attr_reader :cities, :ocean_network, :farms, :boat_networks
    def initialize
        @cities = {}
        @ocean_network = OceanNetwork.new
        @farms = {}
        @boat_networks = {}
    end
    
    def execute_file_shipment
        initialize
        
        @ocean_network.read_map!
        
        game_content = read_game_file_content
        
        game_content["FARM"].each do |line|
            farm = Farm.from_file_line(line, @ocean_network)
            @farms[farm.name] = farm
        end
        
        game_content["BOAT"].each do |line|
            boat_network = BoatNetwork.from_file_line(line, @ocean_network)
            @boat_networks[boat_network.name] = boat_network
        end
        
        game_content["CITY"].each do |line|
            city_node = CityNode.from_file_line(line, @ocean_network)
            @cities[city_node.name] = city_node
        end
        
        game_content["SHIPMENT"].each do |line|
            return execute_shipment_from(line.gsub(/[^a-zA-Z0-9_-]/, ""))
        end
    end
    
    def read_game_file_content
        file = File.new("indonesia_game.txt")
        cur_content = []
        all_content = {"" => cur_content}
        while (line=file.gets)
            if line =~ /\[[a-zA-Z0-1_-]*\]/
                section = line[1..-1][/[a-zA-Z0-1_-]*/]
                cur_content = []
                all_content[section] = cur_content
            elsif line.strip.start_with?('#')
            elsif !line.strip.empty?
                cur_content.push(line)
            end
        end
        file.close
        
        all_content
    end
    
    def execute_shipment_from(farm_name)
        farm = @farms[farm_name]
        if !farm
            return nil
        end
        
        boat_node_index = {}
        boats_capacity = []
        index = 0
        @boat_networks.each_value do |boat_network|
            boat_network.boat_nodes.each do |boat_node|
                boat_node_index[boat_node] = index
                boats_capacity.push(boat_network.cargo_capacity)
                index += 1
            end
        end
        $ssf.boat_node_index = boat_node_index
        
        
        city_node_index = {}
        cities_need = []
        index = 0
        @cities.each_value do |city_node|
            city_node_index[city_node] = index
            cities_need.push(city_node.prod_needs)
            index += 1
        end
        $ssf.city_node_index = city_node_index
        
        
        farm_node_index = {}
        farm_prod = []
        index = 0
        farm.farm_nodes.each do |farm_node|
            farm_node_index[farm_node] = index
            farm_prod.push(farm_node.prod_count)
            index += 1
        end
        $ssf.farm_node_index = farm_node_index
        
        $ssf.farm_owner = farm.owner
        $ssf.initial_total_prod = farm_prod.sum
        
        sum = 0
        farm.reachable_cities.each do |city|
            sum += city.prod_needs
        end
        $ssf.most_shipable = sum
        
        first_state = ShippingState.initial_state(cities_need, boats_capacity, farm_prod)
        ai = AI.new
        
        ai.find_optimal_shipping(farm, first_state).reverse.each do |state|
            puts state.cur_prod_location
        end
        
        nil
    end
    
end

class CityNode
    attr_accessor :name, :prod_needs
    attr_reader :linked_oceans
    def initialize(name, prod_needs=1)
        @name = name
        @prod_needs = prod_needs.to_i
        @linked_oceans = []
    end
    
    def self.from_file_line(line, ocean_network)
        line = line.gsub(/[^:$,a-zA-Z0-9_-]/, "")
        name, _, rest = line.partition("$")
        prod_needs, _, links = rest.partition(":")
        
        city_node = CityNode.new(name, prod_needs)
        links = links.split(",")
        
        links.each do |link|
            ocean = ocean_network[link]
            ocean.add_linked_city(city_node)
            city_node.add_ocean(ocean)
        end
        
        city_node
    end
    
    def add_ocean(ocean_node)
        @linked_oceans.push(ocean_node)
    end
    
    def rem_ocean(ocean_node)
        @linked_oceans.delete(ocean_node)
    end
end


class OceanNetwork
    attr_reader :ocean_nodes
    def initialize
        @ocean_nodes = {}
    end
    
    def read_map!
        file = File.new("indonesia_map.txt")
        while (line=file.gets)
            line = line.gsub(/[^:,a-zA-Z0-9_-]/, "")
            node, _, links = line.partition(":")
            if node.empty?
                next
            end
            links = links.split(",")
            
            node = get_create_node(node)
            links.each do |link|
                if ! link.empty?
                    link = get_create_node(link)
                    node.add_linked_ocean(link)
                    link.add_linked_ocean(node)
                end
            end
        end
        file.close
        
    end
    
    def [](name)
        @ocean_nodes[name]
    end
    
    private
    def get_create_node(node_name)
        if @ocean_nodes.include?(node_name)
            return @ocean_nodes[node_name]
        else
            node = OceanNode.new(node_name)
            @ocean_nodes[node_name] = node
            return node
        end
        
    end
    
end

class OceanNode
    attr_reader :boats, :linked_oceans, :linked_cities, :name
    
    def initialize(name)
        @name = name
        @linked_oceans = [] # Array of OceanNode
        @linked_cities = [] # Array of CityNode
        @boats = [] # Array of BoatNode
    end
    
    def add_linked_ocean(ocean_node)
        @linked_oceans.push(ocean_node)
        @boats.each do |boat|
            boat.add_linked_ocean(ocean_node)
        end
    end
    
    def rem_linked_ocean(ocean_node)
        @linked_oceans.delete(ocean_node)
        @boats.each do |boat|
            boat.rem_linked_ocean(ocean_node)
        end
    end
    
    def add_linked_city(city_node)
        @linked_cities.push(city_node)
        @boats.each do |boat|
            boat.add_linked_city(city_node)
        end
    end
    
    def rem_linked_city(city_node)
        @linked_cities.delete(city_node)
        @boats.each do |boat|
            boat.rem_linked_city(city_node)
        end
    end
    
    def add_boat(boat_node)
        @linked_oceans.each do |ocean|
            ocean.boats.each do |boat|
                if boat_node.network == boat.network
                    boat.add_linked_boat(boat_node)
                    boat_node.add_linked_boat(boat)
                end
            end
        end
        @boats.push(boat_node)
    end
    
    def rem_boat(boat_node)
        @linked_oceans.each do |ocean|
            ocean.boats.each do |boat|
                if boat_node.network == boat.network
                    boat.rem_linked_boat(boat_node)
                    boat_node.rem_linked_boat(boat)
                end
            end
        end
        @boats.delete(boat_node)
    end
    
    def boat_networks
        networks = Set.new
        @boats.each do |boat|
            networks.add(boat.network)
        end
        Array(networks)
    end
end

class BoatNetwork
    attr_accessor :owner, :name, :cargo_capacity
    attr_reader :boat_nodes
    def initialize(owner, name, cargo_capacity=1)
        @owner = owner
        @name = name
        @cargo_capacity = cargo_capacity.to_i
        @boat_nodes = [] # Array of BoatNode
    end
    
    def self.from_file_line(line, ocean_network)
        line = line.gsub(/[^:$|,a-zA-Z0-9_-]/, "")
        owner, _, rest = line.partition("|")
        name, _, rest = rest.partition("$")
        cargo_capacity, _, links = rest.partition(":")
        
        boat_network = BoatNetwork.new(owner, name, cargo_capacity)
        links = links.split(",")
        
        links.each do |link|
            ocean = ocean_network[link]
            boat_node = BoatNode.new(boat_network, ocean)
            boat_network.add_boat(boat_node)
            ocean.add_boat(boat_node)
        end
        
        boat_network
    end
    
    def add_boat(boat_node)
        @boat_nodes.push(boat_node)
    end
    
    def rem_boat(boat_node)
        @boat_nodes.delete(boat_node)
    end
    
    def linked_cities
        cities = Set.new
        @boat_nodes.each do |boat|
            cities.merge(boat.linked_cities)
        end
        Array(cities)
    end
    
end

class BoatNode
    attr_reader :ocean_node, :linked_boats, :linked_cities
    attr_accessor :network
    
    def initialize(network, ocean_node)
        @ocean_node = ocean_node
        @network = network
        @linked_boats = [] # Array of BoatNode
        @linked_cities = [] # Array of CityNode
    end
    
    def inspect
        "BoatNode<network: #{@network.name} ocean: #{ocean_node.name}>"
    end
    
    def to_s
        inspect
    end
    
    def add_linked_boat(boat_node)
        @linked_boats.push(boat_node)
    end
    
    def rem_linked_boat(boat_node)
        @linked_boats.delete(boat_node)
    end
    
    def add_linked_city(city_node)
        @linked_cities.push(city_node)
    end
    
    def rem_linked_city(city_node)
        @linked_cities.delete(city_node)
    end
end


class Farm
    attr_accessor :owner, :name
    attr_reader :farm_nodes
    def initialize(owner, name)
        @farm_nodes = []
        @owner = owner
        @name = name
    end
    
    def self.from_file_line(line, ocean_network)
        line = line.gsub(/[^:$|,a-zA-Z0-9_-]/, "")
        blocks = line.split("|")
        owner = blocks[0]
        name = blocks[1]
        
        farm_strings = blocks[2..-1]
        farm = Farm.new(owner, name)
        
        farm_strings.each do |farm_string|
            name, _, rest = farm_string.partition("$")
            production,_,links = rest.partition(":")
            links = links.split(",")
            
            farm_node = FarmNode.new(name, production)
            farm.add_node(farm_node)
            links.each do |link|
                link = ocean_network[link]
                farm_node.add_ocean(link)
            end
        end
        
        farm
    end
    
    def add_node(farm_node)
        @farm_nodes.push(farm_node)
    end
    
    def rem_node(farm_node)
        @farm_nodes.delete(farm_node)
    end
    
    def linked_oceans
        oceans = Set.new
        @farm_nodes.each do |farm_node|
            oceans.merge(farm_node.linked_oceans)
        end
        Array(oceans)
    end
    
    def linked_boats
        boats = Set.new
        @farm_nodes.each do |farm_node|
            boats.merge(farm_node.boats)
        end
        Array(boats)
    end
    
    def linked_networks
        networks = Set.new
        @farm_nodes.each do |farm_node|
            networks.merge(farm_node.linked_networks)
        end
        Array(networks)
    end
    
    def reachable_cities
        cities = Set.new
        @farm_nodes.each do |farm_node|
            cities.merge(farm_node.reachable_cities)
        end
        Array(cities)
    end
    
    
end

class FarmNode
    attr_accessor :name, :prod_count
    attr_reader :linked_oceans

    def initialize(name, prod_count=1)
        @name = name
        @prod_count = prod_count.to_i
        @linked_oceans = [] # Array of OceanNode
    end
    
    def add_ocean(ocean_node)
        @linked_oceans.push(ocean_node)
    end
    
    def rem_ocean(ocean_node)
        @linked_oceans.delete(ocean_node)
    end
    
    def linked_boats
        boats = Set.new
        @linked_oceans.each do |ocean|
            boats.merge(ocean.boats)
        end
        Array(boats)
    end
    
    def linked_networks
        boat_networks = Set.new
        linked_boats.each do |boat|
            boat_networks.add(boat.network)
        end
        Array(boat_networks)
    end
    
    def reachable_cities
        cities = Set.new
        linked_networks.each do |network|
            cities.merge(network.linked_cities)
        end
        Array(cities)
    end
    
end

class ShippingStateFormat
    attr_accessor :boat_node_index, :city_node_index, :farm_node_index
    attr_accessor :farm_owner, :initial_total_prod, :most_shipable
    
    @boat_node_index = {}
    @city_node_index = {}
    @farm_node_index = {}
    @farm_owner = ""
    @initial_total_prod = 0
    @most_shipable = 0
end
# Ugly global? Bite me
$ssf = ShippingStateFormat.new


class ShippingState   
    attr_accessor :city_need_left, :boat_capacity_left, :farm_prod_left
    attr_accessor :cur_prod_location, :prev_state, :cur_cost
    
    def self.initial_state(cities_need, boats_capacity, farm_prod)
        ns = ShippingState.new
        ns.city_need_left = cities_need
        ns.boat_capacity_left = boats_capacity
        ns.farm_prod_left = farm_prod
        ns.cur_prod_location = nil
        ns.prev_state = nil
        ns.cur_cost = 0
        
        ns
    end
    
    def ==(other)
        other.equal?(self) ||
        (self.class.equal?(other.class) &&
        other.city_need_left == @city_need_left &&
        other.boat_capacity_left == @boat_capacity_left &&
        other.farm_prod_left == @farm_prod_left &&
        other.cur_prod_location == @cur_prod_location)
    end
    
    def eql?(other)
        self == other
    end
    
    def inspect
        "ShippingState<cur_prod_location: #{cur_prod_location} city_needs: #{@city_need_left} boat_capacity: #{@boat_capacity_left} farm_prod_left: #{@farm_prod_left}>"
    end
    
    def to_s
        inspect
    end
    
    def hash
        (@city_need_left.hash + @boat_capacity_left.hash + 
         @farm_prod_left.hash + @cur_prod_location.hash + @cur_cost.hash)
    end
    
    def shipped_count
        $ssf.initial_total_prod - @farm_prod_left.sum
    end
    
    def can_extract_from_node(from_farm_node)
        @farm_prod_left[$ssf.farm_node_index[from_farm_node]] > 0
    end
    
    def can_extract_to_boat(to_boat_node)
        @boat_capacity_left[$ssf.boat_node_index[to_boat_node]] > 0
    end
    
    def next_extract(from_farm_node, to_boat_node)
        ns = ShippingState.new
        ns.city_need_left = @city_need_left
        ns.boat_capacity_left = @boat_capacity_left.clone
        ns.farm_prod_left = @farm_prod_left.clone
        ns.cur_prod_location = to_boat_node
        ns.prev_state = self
        ns.cur_cost = @cur_cost
        
        if to_boat_node.network != $ssf.farm_owner
            ns.cur_cost += 1
        end
        
        index = $ssf.farm_node_index[from_farm_node]
        ns.farm_prod_left[index] -= 1
        index = $ssf.boat_node_index[to_boat_node]
        ns.boat_capacity_left[index] -= 1
        
        ns
    end
    
    def can_move_prod_to(to_boat_node)
        @boat_capacity_left[$ssf.boat_node_index[to_boat_node]] > 0
    end
    
    def next_move_prod_to(to_boat_node)
        ns = ShippingState.new
        ns.city_need_left = @city_need_left
        ns.boat_capacity_left = @boat_capacity_left.clone
        ns.farm_prod_left = @farm_prod_left
        ns.cur_prod_location = to_boat_node
        ns.prev_state = self
        ns.cur_cost = @cur_cost
        
        if to_boat_node.network != $ssf.farm_owner
            ns.cur_cost += 1
        end
        
        index = $ssf.boat_node_index[to_boat_node]
        ns.boat_capacity_left[index] -= 1
        
        ns
    end
    
    def can_move_prod_to_city(to_city_node)
        @city_need_left[$ssf.city_node_index[to_city_node]] > 0
    end
    
    def next_move_prod_to_city(to_city_node)
        ns = ShippingState.new
        ns.city_need_left = @city_need_left.clone
        ns.boat_capacity_left = @boat_capacity_left
        ns.farm_prod_left = @farm_prod_left
        ns.cur_prod_location = nil
        ns.prev_state = self
        ns.cur_cost = @cur_cost
        
        index = $ssf.city_node_index[to_city_node]
        ns.city_need_left[index] -= 1
        
        ns
    end
end

class AI
    
    def find_optimal_shipping(farm, node_start)
        @farm = farm
        best_first(node_start)
    end
    
    def best_first(node_start)
        #### Speed improvements:
        #### Do all options with own networks first, so at no cost, because these
        ####    are obviously used as much as possible, unless you want to do some advanced strategy
        ####    where you give more money to another player in order to make him stronger against 
        ####    another player or some other crazy stuff.
        ####    Doing this would also allow us to clear the closed set when we switch to next_open,
        ####    since we can't land on those previous states with lower costs. This would make the algorithm
        ####    must more memory efficient and slightly faster since it limits the growth of the set...
        
        cur_open = [] # states with the same cost as current that have not yet been tested
        next_open = [] # states with the cost+1 as current that have not yet been tested
        
        closed = Set.new()
        
        cur_solutions = []
        solution_shipped_count = 0
        
        node_current = node_start
        cur_open.push(node_start)
        while !cur_open.empty? || !next_open.empty? do
            if cur_open.empty?
                cur_open = next_open
                next_open = []
            end
            node_current = cur_open.pop()
            
            if possible_goal?(node_current)
                count = node_current.shipped_count
                if count > solution_shipped_count
                    solution_shipped_count = count
                    cur_solutions = [node_current]
                elsif count == solution_shipped_count
                    cur_solutions.push(node_current)
                end
            end
            closed.add(node_current)
            
            next_shipping_states(node_current).each do |node_successor|
                if closed.include?(node_successor) || open.include?(node_successor)
                    next
                end
                if node_curent.cur_cost < node_successor.cur_cost
                    next_open.push(node_successor)
                else
                    cur_open.push(node_successor)
                end
            end
            
        end
        
        if cur_solution.empty?
            puts "No solution can ship anything"
            return []
        end
        
        puts "Cost: #{cur_solutions[0].cur_cost}"
        
        format_node_path(cur_solutions[0])
    end
    
    def format_node_path(end_node)
        backtrack = [end_node]
        node = end_node
        while node.prev_state
            node = node.prev_state
            backtrack.push(node)
        end
        
        backtrack
    end
        
    def possible_goal?(shipping_state)
        shipping_state.cur_prod_location.nil?
    end

    def next_shipping_states(shipping_state)
        # For every nodes available (cities included), check if any of the
        # nodes of the path up to now touches this possible new path. If so, don't 
        # use them as next_shipping_states, since there is an obviously better path
        # to get to it.
        
        if shipping_state.cur_prod_location
            # Currently shipping an item
            
            cant_go = Set.new
            temp_state = shipping_state.prev_state
            
            while temp_state.cur_prod_location
                # Going back would be a waste
                cant_go.add(temp_state.cur_prod_location)
                
                temp_state.cur_prod_location.linked_boats.each do |boat|
                    # We already passed besides these boats, so going there now is a waste
                    cant_go.add(boat)
                end
                
                temp_state.cur_prod_location.linked_cities.each do |city|
                    # We already passed besides these cities, so going there now is a waste
                    cant_go.add(city)
                end
                
                temp_state = temp_state.prev_state
            end
            
            next_states = []
            shipping_state.cur_prod_location.linked_boats.each do |boat|
                if !cant_go.include?(boat) && shipping_state.can_move_prod_to(boat)
                    next_states.push(shipping_state.next_move_prod_to(boat))
                end
            end
            
            shipping_state.cur_prod_location.linked_cities.each do |city|
                if !cant_go.include?(city)  && shipping_state.can_move_prod_to_city(city)
                    next_states.push(shipping_state.next_move_prod_to_city(city))
                end
            end
            
            return next_states
        else
            # Need to extract an item
            
            if $ssf.most_shipable == shipping_state.shipped_count
                # All reacheable cities have no more needs.
                return []
            end
            
            next_states = []
            @farm.farm_nodes.each do |farm_node|
                if !shipping_state.can_extract_from_node(farm_node)
                    next
                end
                farm_node.linked_oceans.each do |ocean|
                    ocean.boats.each do |boat|
                        if shipping_state.can_extract_to_boat(boat)
                            next_states.push(shipping_state.next_extract(farm_node, boat))
                        end
                    end
                end
            end
            
            return next_states
        end
    end
end


class Array
    def sum
        self.inject{|sum,x| sum + x }
    end
end

