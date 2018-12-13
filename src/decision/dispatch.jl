##########################################################################
# Copyright 2017 Samuel Ridler.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################

# return true if ambulance is available for dispatch to a call
function isAmbAvailableForDispatch(sim::Simulation, ambulance::Ambulance, call::Call)
	status = ambulance.status
	if status == ambIdleAtStation || status == ambGoingToStation
		return true
	elseif status == ambGoingToCall && sim.calls[ambulance.callIndex].priority != highPriority && call.priority == highPriority
		return true
	end
	return false
end

# return the index of the nearest available ambulance to dispatch to a call
function findNearestFreeAmbToCall!(sim::Simulation, call::Call)
	
	# nearest node to call, this is independent of chosen ambulance
	(node2, dist2) = (call.nearestNodeIndex, call.nearestNodeDist)
	travelMode = getTravelMode!(sim.travel, sim.responseTravelPriorities[call.priority], sim.time)
	time2 = offRoadTravelTime(travelMode, dist2) # time to reach nearest node
	
	# for ambulances that can be dispatched, find the one with shortest travel time to call
	ambIndex = nullIndex # nearest free ambulance
	minTime = Inf
	for amb in sim.ambulances
		if isAmbAvailableForDispatch(sim, amb, call)
			(node1, time1) = getRouteNextNode!(sim, amb.route, travelMode.index, sim.time) # next/nearest node in ambulance route
			travelTime = shortestPathTravelTime(sim.net, travelMode.index, node1, node2) # time spent on network
			travelTime += time1 + time2 # add time to get on and off network
			if minTime > travelTime
				ambIndex = amb.index
				minTime = travelTime
			end
		end
	end
	
	return ambIndex
end
