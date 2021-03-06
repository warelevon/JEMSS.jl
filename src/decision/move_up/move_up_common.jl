# common move-up functions

function isAmbAvailableForMoveUp(ambulance::Ambulance)
	status = ambulance.status
	if status == ambIdleAtStation || status == ambGoingToStation # || status == ambMovingUp
		return true
	end
	return false
end

# for an ambulance, gives travel time for it to travel to each station
function ambMoveUpTravelTimes!(sim::Simulation, ambulance::Ambulance)
	
	# shorthand:
	net = sim.net
	travel = sim.travel
	stations = sim.stations
	priority = lowPriority # default travel priority for this function
	
	travelMode = getTravelMode!(travel, priority, sim.time)
	(node1, time1) = getRouteNextNode!(sim, ambulance.route, travelMode.index, sim.time) # next/nearest node in ambulance route
	
	# get travel times to each station
	numStations = length(stations)
	ambToStationTimes = Vector{Float}(numStations)
	for i = 1:numStations
		station = stations[i]
		if ambulance.stationIndex == station.index && ambulance.status == ambIdleAtStation
			# ambulance already idle at this station, travel time is 0
			ambToStationTimes[i] = 0.0
		else
			# lookup travel time from node1 to station
			(travelTime, rNodes) = shortestPathTravelTime(net, travelMode.index, node1, station.nearestNodeIndex)
			time2 = offRoadTravelTime(travelMode, station.nearestNodeDist)
			ambToStationTimes[i] = time1 + travelTime + time2 # on and off road travel times
		end
	end
	
	return ambToStationTimes
end

function createStationPairs(sim::Simulation, travelMode::TravelMode;
	maxPairsPerStation::Int = Inf, maxPairSeparation::Float = Inf)
	
	# shorthand:
	net = sim.net
	travel = sim.travel
	map = sim.map
	stations = sim.stations
	numStations = length(stations)
	priority = lowPriority # default travel priority for this function
	
	maxPairsPerStation = min(maxPairsPerStation, numStations)
	
	# calculate travel times between each pair of stations
	stationToStationTimes = zeros(Float, numStations, numStations) #Array{Float,2}(numStations,numStations)
	for i = 1:numStations, j = 1:numStations
		if i != j
			# check travel time from station i to j
			(travelTime, rNodes) = shortestPathTravelTime(net, travelMode.index, stations[i].nearestNodeIndex, stations[j].nearestNodeIndex)
			travelTime += offRoadTravelTime(travelMode, stations[i].nearestNodeDist)
			travelTime += offRoadTravelTime(travelMode, stations[j].nearestNodeDist)
			stationToStationTimes[i,j] = travelTime
		end
	end
	
	areStationsPaired = Array{Bool,2}(numStations,numStations) # areStationsPaired[i,j] = false if stations i, j, should not be paired
	areStationsPaired[:] = true
	sortedTimes = sort(stationToStationTimes, 2)
	areStationsPaired .*= (stationToStationTimes .<= sortedTimes[:, maxPairsPerStation])
	areStationsPaired .*= (stationToStationTimes .<= maxPairSeparation)
	
	# make sure that areStationsPaired is symmetric
	areStationsPaired .*= areStationsPaired'
	
	# convert areStationsPaired to stationPairs
	stationPairs = Vector{Vector{Int}}(0) # stationPairs[i][k] gives kth station in pair i (k = 1,2)
	for i = 1:numStations, j = i+1:numStations
		if areStationsPaired[i,j]
			push!(stationPairs, [i,j])
		end
	end
	
	return stationPairs
end

function moveUpNull()
	return Ambulance[], Station[]
end
