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

type Location
	x::Float # latitude, or other
	y::Float # longitude, or other
	
	Location() = new(nullX, nullY)
	Location(x,y) = new(x,y)
end

type Point
	index::Int
	location::Location
	value::Any
	
	# node nearest to location
	nearestNodeIndex::Int
	nearestNodeDist::Float
	
	Point() = new(nullIndex, Location(), nothing,
		nullIndex, nullDist)
end

type Node
	index::Int
	location::Location
	offRoadAccess::Bool # if node can be used to get on-road and off-road
	
	fields::Dict{String,Any} # additional data, not used by simulation
	
	Node() = new(nullIndex, Location(), true,
		Dict{String,Any}())
end

type Arc
	index::Int
	fromNodeIndex::Int
	toNodeIndex::Int
	
	fields::Dict{String,Any} # additional data, not used by simulation
	
	Arc() = new(nullIndex, nullIndex, nullIndex,
		Dict{String,Any}())
end

# graph data for network (actually a digraph)
type Graph
	# parameters:
	isReduced::Bool
	nodes::Vector{Node}
	arcs::Vector{Arc}
	
	light::LightGraphs.DiGraph
	fadjList::Vector{Vector{Int}} # shorthand for light.fadjlist; fadjList[i] gives nodes that are connected to node i by an outgoing arc from node i
	
	# for full graph:
	nodePairArcIndex::SparseMatrixCSC{Int,Int} # for node indices i,j, nodePairArcIndex[i,j] should return arc index for node pair
	# cannot always use nodePairArcIndex for reduced graph, there may be more than one arc from node i to j, use spNodePairArcIndex instead
	
	Graph(isReduced::Bool) = new(isReduced, [], [],
		LightGraphs.DiGraph(), [],
		spzeros(Int, 0, 0))
end

# travel data for network
type NetTravel
	# parameters:
	isReduced::Bool
	modeIndex::Int
	arcTimes::Vector{Float} # arcTimes[i] gives travel time along arc i
	
	# for use in reduced graph:
	spTimes::Array{FloatSpTime,2} # spTimes[i,j] = shortest path time between node i and j
	spFadjIndex::Array{IntFadj,2} # for shortest path from rNode i to j, spFadjIndex[i,j] gives the index (in fadjList[i], see Graph) of the successor rNode of i for this path
	spNodePairArcIndex::SparseMatrixCSC{Int,Int} # spNodePairArcIndex[i,j] = index of arc incident to nodes i,j, if it provides shortest travel time
	spFadjArcList::Vector{Vector{Int}} # spFadjArcList[i][j] gives index of rArc from rNode[i] to jth outoing rNode of rNode[i] (i.e. rGraph.fadjList[i][j])
	
	# for use in full graph:
	fNodeToRNodeTime::Vector{Dict{Int,Float}} # fNodeToRNodeTime[i][j] gives time from fNode[i] to rNode[j], as long as rNode[j] is in fNodeToRNodes[i] (see type Network)
	fNodeFromRNodeTime::Vector{Dict{Int,Float}} # fNodeFromRNodeTime[i][j] gives time to fNode[i] from rNode[j], as long as rNode[j] is in fNodeFromRNodes[i] (see type Network)
	rArcFNodesTimes::Vector{Vector{Float}} # rArcFNodesTimes[i][k] gives travel time from rArc[i].fromNodeIndex to rArcFNodes[i][k]
	
	# useful object to/from node data, for full graph (see commonFNodes in Network):
	commonFNodeToFNodeTime::Array{Float,2} # commonFNodeToFNodeTime[i,j] gives shortest path time from commonFNodes[i] to fNode j
	fNodeToCommonFNodeTime::Array{Float,2} # fNodeToCommonFNodeTime[i,j] gives shortest path time from fNode i to commonFNodes[j]
	commonFNodeToFNodeRNodes::Array{Vector{Int},2} # commonFNodeToFNodeRNodes[i,j] gives start and end rNode for shortest path from commonFNodes[i] to fNode j
	fNodeToCommonFNodeRNodes::Array{Vector{Int},2} # fNodeToCommonFNodeRNodes[i,j] gives start and end rNode for shortest path from fNode i to commonFNodes[j]
	fNodeNearestHospitalIndex::Vector{Int} # fNodeNearestHospitalIndex[i] gives index of nearest hospital from fNode[i]
	
	NetTravel(isReduced::Bool) = new(isReduced, nullIndex, [],
		Array{FloatSpTime,2}(0,0), Array{IntFadj,2}(0,0), spzeros(Int, 0, 0), [],
		[], [], [],
		Array{Float,2}(0,0), Array{Float,2}(0,0), Array{Vector{Int},2}(0,0), Array{Vector{Int},2}(0,0), [])
end

type Network
	fGraph::Graph # full graph
	rGraph::Graph # reduced graph
	
	# travel data for each graph:
	fNetTravels::Vector{NetTravel} # fNetTravels[i] gives fGraph travel data for travel mode i
	rNetTravels::Vector{NetTravel} # rNetTravels[i] gives rGraph travel data for travel mode i
	
	# for converting between full and reduced graph:
	rNodeFNode::Vector{Int} # rNodeFNode[i] returns index of rNode i in fGraph
	fNodeRNode::Vector{Int} # fNodeRNode[i] returns index of fNode i in rGraph, nullIndex if not in rGraph
	rArcFNodes::Vector{Vector{Int}} # rArcFNodes[i] gives array of fNode indices that belong to rArc i (ordered: fromNodeIndex -> toNodeIndex)
	fNodeRArcs::Vector{Vector{Int}} # fNodeRArcs[i] gives indices of rArcs that fNode[i] is on
	rArcFNodeIndex::Vector{Dict{Int,Int}} # rArcFNodeIndex[i][j] gives index that fNode[j] appears in rArc[i]; should be same as find(rArcFNodes[i] .== j), so rArcFNodes[i][rArcFNodeIndex[i][j]] = j
	fNodeToRNodes::Vector{Vector{Int}} # fNodeToRNodes[i] gives indices of rNodes that fNode[i] can travel to, and is "near" ("near" meaning that the fNode is on an rArc incident to rNode, or fNode is rNode in rGraph; it is similar to adjacency)
	fNodeFromRNodes::Vector{Vector{Int}} # fNodeFromRNodes[i] gives indices of rNodes that can travel to fNode[i], and is "near"
	fNodeToRNodeNextFNode::Vector{Dict{Int,Int}} # fNodeToRNodeNextFNode[i][j] gives index of fNode after fNode[i] on path to rNode[j], where j is in fNodeToRNodes[i]. Needed to find path from an fNode to an rNode
	
	# fNodes that are common start/end points for travel (e.g, fNodes nearest to stations, hospitals):
	commonFNodes::Vector{Int} # list of common fNodes; = find(isFNodeCommon)
	isFNodeCommon::Vector{Bool} # isFNodeCommon[i] = true if fNode i is common, false otherwise
	fNodeCommonFNodeIndex::Vector{Int} # fNodeCommonFNodeIndex[i] gives index of fNode i in commonFNodes, if isFNodeCommon[i] = true
	
	Network() = new(Graph(false), Graph(true),
		[], [],
		[], [], [], [], [], [], [], [],
		[], [], [])
end

# travel information, for on-road and off-road
type TravelMode
	index::Int
	
	offRoadSpeed::Float
	
	fNetTravel::NetTravel # reference to single fNetTravel in type Network
	rNetTravel::NetTravel # reference to single rNetTravel in type Network
	
	TravelMode() = new(nullIndex,
		nullTime,
		NetTravel(false), NetTravel(true))
end

# for storing travel modes, travel sets (a set of travel modes apply to each time period),
# and conditions for when to use each travel set/mode
type Travel
	numModes::Int # number of travel modes
	numSets::Int # number of sets of travel modes; each set may contain multiple travel modes e.g. for different combinations of travel priorities and ambulance classes. Different sets can overlap, by containing the same travel modes.
	
	modes::Vector{TravelMode}
	modeLookup::Array{Int,2} # modeLookup[i,j] = index of travel mode to use for travel set i, travel priority j. Change this variable according to modelling needs
	
	setsStartTimes::Vector{Float} # setsStartTimes[i] gives time at which travel set setsTimeOrder[i] should be started (setsStartTimes[i+1] or Inf gives end time)
	setsTimeOrder::Vector{Int} # setsTimeOrder[i] gives travel set to start using at time setsStartTimes[i]
	recentSetsStartTimesIndex::Int # index of most recently used value in setsStartTimes (and setsTimeOrder), should only ever increase in value
	
	Travel() = new(nullIndex, nullIndex,
		[], Array{Int,2}(0,0),
		[], [], nullIndex)
end

# for storing ambulance routes
# routes include a path (on fGraph), and may start/end off the graph
type Route
	priority::Priority # travel priority
	travelModeIndex::Int
	
	# start and end locations and times
	startLoc::Location
	startTime::Float
	endLoc::Location
	endTime::Float
	
	# start and end nodes and times
	startFNode::Int # index of first fNode in route
	startFNodeTime::Float # time at which startFNode is reached
	startRNode::Int # index of first rNode in route
	startRNodeTime::Float # time at which startRNode is reached
	endRNode::Int # index of last rNode in route
	endRNodeTime::Float # time at which endRNode is reached
	endFNode::Int # index of last fNode in route
	endFNodeTime::Float # time at which endFNode is reached
	
	firstRArc::Int # index of first rArc in route; = nullIndex if startFNode == endFNode
	
	## fields that vary throughout the route are below here
	## most of the route code assumes that these fields only change to move "forward" through the route
	
	# recent rArc visited ("recent" means it is from the most recent route update/query)
	recentRArc::Int # index of rArc recently visited
	recentRArcStartTime::Float # time that travel on rArc started / would have started if had travelled from first node of recentRArc (can start part way along the arc)
	recentRArcEndTime::Float # time that travel on rArc should end / would end if were travelling to last node of recentRArc (can end part way along the arc)
	
	# recent fNode visited on recentRArc
	recentRArcRecentFNode::Int # index of fNode recently visited on recentRArc, rArcFNodes[recentRArc][recentRArcRecentFNode] gives index of fNode in fGraph
	recentFNode::Int # = rArcFNodes[recentRArc][recentRArcRecentFNode]
	recentFNodeTime::Float # time that recentFNode was reached
	
	# next fNode to visit on recentRArc
	recentRArcNextFNode::Int # recentRArcRecentFNode + 1
	nextFNode::Int # = rArcFNodes[recentRArc][recentRArcNextFNode]
	nextFNodeTime::Float # time that nextFNode will be reached
	
	Route() = new(nullPriority, nullIndex,
		Location(), nullTime, Location(), nullTime,
		nullIndex, nullTime, nullIndex, nullTime, nullIndex, nullTime, nullIndex, nullTime,
		nullIndex,
		nullIndex, nullTime, nullTime,
		nullIndex, nullIndex, nullTime,
		nullIndex, nullIndex, nullTime)
end

type Event
	index::Int # index of event in list of events that have occurred (not for sim.eventList)
	parentIndex::Int # index of parent event
	form::EventForm # "type" is taken
	time::Float
	ambIndex::Int
	callIndex::Int
	stationIndex::Int # for now, only use this for resimulation, otherwise use ambulances[ambIndex].stationIndex
	
	
	Event() = new(nullIndex, nullIndex, nullEvent, nullTime, nullIndex, nullIndex, nullIndex)
end

type Ambulance
	index::Int
	status::AmbStatus
	stationIndex::Int
	callIndex::Int
	route::Route
	event::Event # next/current event, useful for deleting next event from eventList
	class::AmbClass # class/type of ambulance
	# schedule::Schedule # to be added
	
	# for animation:
	currentLoc::Location
	movedLoc::Bool
	
	# for statistics:
	totalTravelTime::Float # this should only be updated after finishing each route / sim end
	totalBusyTime::Float # total time that ambulance has been busy
	# totalStationTime::Float # total time spent at station
	numCallsTreated::Int # total number of calls that ambulance provided treatment for
	numCallsTransferred::Int # total number of calls transferred to hospital
	numDiversions::Int # number of times that ambulance is diverted from one call to another
	atStationDispatches::Int # total number of dispatches while at station
	onRoadDispatches::Int # total number of dispatches while on road
	afterServiceDispatches::Int # total number of dispatches directly after providing service at callout
	
	Ambulance() = new(nullIndex, ambNullStatus, nullIndex, nullIndex, Route(), Event(), nullAmbClass,
		Location(), false,
		0.0, 0.0, 0, 0, 0, 0, 0, 0)
end

type Call
	index::Int
	status::CallStatus
	ambIndex::Int
	priority::Priority
	transfer::Bool # true if requires transfer to hospital
	hospitalIndex::Int # hospital (if any) that ambulance is transferred to. If hospitalIndex == nullIndex, will transfer to nearest hospital
	location::Location # where call occurs
	
	arrivalTime::Float # time at which call arrives
	dispatchDelay::Float # delay between call arrival and considering dispatching an ambulance
	onSceneDuration::Float # time spent at call location
	transferDuration::Float # for hospital transfer
	
	# node nearest to call location:
	nearestNodeIndex::Int
	nearestNodeDist::Float
	
	# for animation:
	currentLoc::Location
	movedLoc::Bool
	
	# for statistics:
	dispatchTime::Float # time at which final ambulance was dispatched (= arrivalTime + dispatchDelay, unless call queued/bumped)
	ambArrivalTime::Float # time at which ambulance arrives on-site
	responseTime::Float # time (duration) between call arrival and ambulance arrival at call location
	hospitalArrivalTime::Float # time at which ambulance arrives at hospital
	numBumps::Int # total number of times that call gets bumped
	wasQueued::Bool # whether call was queued or not
	
	Call() = new(nullIndex, callNullStatus, nullIndex, nullPriority, true, nullIndex, Location(),
		nullTime, nullTime, nullTime, nullTime,
		nullIndex, nullDist,
		Location(), false,
		nullTime, nullTime, nullTime, nullTime, 0, false)
end

type Hospital
	index::Int
	location::Location
	nearestNodeIndex::Int
	nearestNodeDist::Float
	
	# for statistics:
	numTransfers::Int # total number of patient transfers from ambulances to hospital
	
	Hospital() = new(nullIndex, Location(), nullIndex, nullDist,
		0)
end

type Station
	index::Int
	location::Location
	capacity::Int # maximum number of ambulances that station can hold
	nearestNodeIndex::Int
	nearestNodeDist::Float
	
	# for statistics:
	# totalAmbIdleTime::Float # total time that ambulances are idle at station
	
	Station() = new(nullIndex, Location(), 0, nullIndex, nullDist)
end

type Map
	xMin::Float
	xMax::Float
	yMin::Float
	yMax::Float
	xRange::Float # xMax - xMin
	yRange::Float # yMax - yMin
	xScale::Float # convert delta(x) to distance
	yScale::Float # convert delta(y) to distance
	# xRangeDist::Float # xRange * xScale
	# yRangeDist::Float # yRange * yScale
	
	Map() = new(nullX, nullX, nullY, nullY, nullDist, nullDist, nullDist, nullDist)
	Map(xMin, xMax, yMin, yMax, xScale, yScale) = new(xMin, xMax, yMin, yMax, xMax - xMin, yMax - yMin, xScale, yScale)
end

# grid search rectangle, part of type Grid
# for keeping track of search progress,
# while looking for nearest node in grid
type GridSearchRect
	# distance of search rectangle borders from a given location
	xDist::Vector{Float}
	yDist::Vector{Float}
	
	# min and max range of grid indices to search next
	ixSearch::Vector{Int}
	iySearch::Vector{Int}
	
	# min and max grid indices of search rectangle, for each direction
	# contains indices of next search also
	ixSearched::Vector{Int}
	iySearched::Vector{Int}
	
	GridSearchRect() = new([nullDist, nullDist], [nullDist, nullDist],
		[nullIndex, nullIndex], [nullIndex, nullIndex],
		[nullIndex, nullIndex], [nullIndex, nullIndex])
	GridSearchRect(ix, iy) = new([nullDist, nullDist], [nullDist, nullDist],
		[ix, ix], [iy, iy],
		[ix, ix], [iy, iy])
end

# grid rectangle, part of type Grid
type GridRect
	nodeIndices::Vector{Int}
	
	GridRect() = new([])
end

# grid breaks map region into rectangles,
# each rectangle stores graph node indices (from full graph)
# this is for quickly finding the nearest node to a location
type Grid
	nx::Int # number of divisions in x direction
	ny::Int # number of divisions in y direction
	xRange::Float # size of divisions in x direction, = map.xRange / nx
	yRange::Float # size of divisions in y direction, = map.yRange / ny
	xRangeDist::Float # distance of divisions in x direction, = xRange * map.xScale
	yRangeDist::Float # distance of divisions in y direction, = yRange * map.yScale
	rects::Array{GridRect,2} # rectangles
	searchRect::GridSearchRect
	
	Grid() = new(nullIndex, nullIndex, nullDist, nullDist, nullDist, nullDist, Array{GridRect,2}(0, 0), GridSearchRect())
	function Grid(map::Map, nx, ny)
		grid = new(nx, ny, nullDist, nullDist, nullDist, nullDist, Array{GridRect,2}(nx, ny))
		for i = 1:nx
			for j = 1:ny
				grid.rects[i,j] = GridRect()
			end
		end
		grid.xRange = map.xRange / nx
		grid.yRange = map.yRange / ny
		grid.xRangeDist = grid.xRange * map.xScale
		grid.yRangeDist = grid.yRange * map.yScale
		grid.searchRect = GridSearchRect()
		return grid
	end
end

# simple raster type
# stores data for rectangular grid of cells,
# cell (i,j) has centre x[i], y[j], and value z[i,j]
# requires at least 2 cells in each direction
type Raster
	# parameters:
	x::Vector{Float}
	y::Vector{Float}
	z::Array{Float,2} # z[i,j] corresponds with x[i], y[j]
	
	nx::Int # length(x)
	ny::Int # length(y)
	dx::Float # x step size
	dy::Float # y step size
	
	Raster() = new([], [], Array{Float,2}(0,0),
		0, 0, 0.0, 0.0)
	function Raster(x, y, z)
		nx = length(x)
		ny = length(y)
		@assert(nx > 1)
		@assert(ny > 1)
		@assert((nx, ny) == size(z))
		dx = (maximum(x) - minimum(x))/(nx-1)
		dy = (maximum(y) - minimum(y))/(ny-1)
		@assert(dx > 0)
		@assert(dy > 0)
		return new(x, y, z, nx, ny, dx, dy)
	end
end

# for generating random locations within a raster,
# where raster z values are proportional to probability of location being
# within corresponding cell (i.e. z values are for categorical distribution),
# and locations are generated uniformly within the cell
type RasterSampler
	raster::Raster
	cellDistrRng::DistrRng # to generate index of raster cell
	cellLocRng::AbstractRNG # rng used when generating location within raster cell
	
	function RasterSampler(raster::Raster, cellRng::AbstractRNG, cellLocRng::AbstractRNG)
		@assert(all(raster.z .>= 0)) # otherwise probability values will be negative
		p = raster.z[:] / sum(raster.z) # pdf for z
		cellSampler = sampler(Categorical(p))
		cellDistrRng = DistrRng(cellSampler, cellRng)
		return new(raster, cellDistrRng, cellLocRng)
	end
	function RasterSampler(raster::Raster, cellSeed::Int, cellLocSeed::Int)
		cellRng = (cellSeed >= 0 ? MersenneTwister(cellSeed) : MersenneTwister(rand(UInt32)))
		cellLocRng = (cellLocSeed >= 0 ? MersenneTwister(cellLocSeed) : MersenneTwister(rand(UInt32)))
		return RasterSampler(raster, cellRng, cellLocRng)
	end
end

# to model call demand for a single priority
# can use multiple demand modes to model change in demand with time, using Demand type
type DemandMode
	# parameters:
	index::Int # mode index
	rasterIndex::Int # index of demand raster in Demand.rasters
	priority::Priority # demand priority
	arrivalRate::Float # demand per day
	
	raster::Raster # reference to Demand.rasters[rasterIndex]
	rasterMultiplier::Float # = arrivalRate / sum(raster.z), to scale raster.z values to match arrivalRate
	
	DemandMode() = new(nullIndex, nullIndex, nullPriority, nullTime,
		Raster(), 0.0)
end

# To model demand (calls).
# Stores demand modes, demand sets (a set of demand modes apply to each time period),
# and conditions for when to use each demand set/mode.
type Demand
	initialised::Bool
	numRasters::Int # number of demand rasters
	numModes::Int # number of demand modes
	numSets::Int # number of sets of demand modes; each set may contain multiple demand modes e.g. for different combinations of call priorities and ambulance classes. Different sets can overlap, by containing the same demand modes.
	
	rasters::Vector{Raster} # demand rasters, to model spatial demand. Raster cell z values are not actual demand, but are proportional to demand
	rasterFilenames::Vector{String} # rasterFilenames[i] gives filename of rasters[i]
	
	modes::Vector{DemandMode}
	modeLookup::Array{Int,2} # modeLookup[i,j] = index of demand mode to use for demand set i, demand priority j. Change this variable according to modelling needs
	
	setsStartTimes::Vector{Float} # setsStartTimes[i] gives time at which demand set setsTimeOrder[i] should be started (setsStartTimes[i+1] or Inf gives end time)
	setsTimeOrder::Vector{Int} # setsTimeOrder[i] gives demand set to start using at time setsStartTimes[i]
	recentSetsStartTimesIndex::Int # index of most recently used value in setsStartTimes (and setsTimeOrder), should only ever increase in value
	
	Demand() = new(false, nullIndex, nullIndex, nullIndex,
		[], [],
		[], Array{Int,2}(0,0),
		[], [], nullIndex)
end

# For a given set of points, coverage time, and travel mode,
# for each station store the points that can be reached by
# travelling from the station within the coverage time.
type PointsCoverageMode
	# parameters:
	index::Int
	points::Vector{Point} # reference to DemandCoverage.points
	coverTime::Float # any demand that can be reached within this time gets additional coverage of 1, otherwise 0. Usually equal to target cover time minus dispatch delay.
	travelMode::TravelMode # reference to a travel mode
	
	pointSets::Vector{Vector{Int}} # pointSets[i] has set of all point indices covered by the same unique set of stations
	stationSets::Vector{Vector{Int}} # stationSets[i] = unique set of stations for pointSets[i]
	stationsCoverPointSets::Vector{Vector{Int}} # stationsCoverPointSets[i] = indices of pointSets covered by station i
	
	PointsCoverageMode() = new(nullIndex, [], nullTime, TravelMode(),
		[], [], [])
end

type DemandCoverage
	# params
	coverTimes::Dict{Priority,Float} # coverTimes[p] gives the target cover time for demand of priority p
	rasterCellNumRows::Int # number of rows of points to create per demand raster cell
	rasterCellNumCols::Int # number of columns of points to create per demand raster cell
	
	initialised::Bool
	points::Vector{Point} # demand is aggregated to points, same points are used for all demand rasters
	nodesPoints::Vector{Vector{Int}} # nodesPoints[i] gives indices of points for which node i is the nearest node
	rastersPointDemands::Vector{Vector{Float}} # rastersPointDemands[i][j] is demand at points[j] for Demand.rasters[i]
	
	pointsCoverageModes::Vector{PointsCoverageMode}
	pointsCoverageModeLookup::Vector{Dict{Float,Int}} # pointsCoverageModeLookup[TravelMode.index][coverTime] gives index of PointsCoverageMode
	pointSetsDemands::Array{Vector{Float},2} # pointSetsDemands[PointsCoverageMode.index, DemandMode.rasterIndex] gives relative demand values for each point set in PointsCoverageMode.pointSets, for Demand.rasters[rasterIndex]. Note that this needs to be multiplied by DemandMode.rasterMultiplier to get absolute (instead of relative) demand values.
	
	DemandCoverage() = new(Dict(), 0, 0,
		false, [], [], [],
		[], [], Array{Vector{Float},2}(0,0))
	
	function DemandCoverage(coverTimes::Dict{Priority,Float}, rasterCellNumRows::Int, rasterCellNumCols::Int)
		dc = demandCoverage = DemandCoverage()
		dc.coverTimes = coverTimes
		dc.rasterCellNumRows = rasterCellNumRows
		dc.rasterCellNumCols = rasterCellNumCols
		return demandCoverage
	end
	
	function DemandCoverage(demandCoverage::DemandCoverage)
		dc = demandCoverage # shorthand
		return DemandCoverage(dc.coverTimes, dc.rasterCellNumRows, dc.rasterCellNumCols)
	end
end

# move up data types
abstract type MoveUpDataType end
type EmptyMoveUpData <: MoveUpDataType end

# compliance table data
type CompTableData <: MoveUpDataType
	# parameters:
	compTable::CompTable # compTable[i,j] = number of ambulances to place at station j, with i total idle ambs
	
	compTableStationSlots::Vector{Vector{Int}} # sum(compTableStationSlots[i] .== j) == compTable[i,j]
	
	# arrays for recycling:
	ambMovable::Vector{Bool} # ambMovable[i] = true if ambulance i is available for move up, false otherwise
	
	CompTableData() = new(CompTable(0,0),
		[],
		[])
end

# dmexclp - dynamic maximum expected coverage location problem
type DmexclpData <: MoveUpDataType
	# parameters:
	busyFraction::Float # fraction for which each ambulance is busy, approximate
	demandWeights::Dict{Priority,Float} # weight of each demand priority on the objective function
	# some other relevant parameters are stored in sim: demand, demandCoverage, responseTravelPriorities
	
	marginalBenefit::Vector{Float} # marginalBenefit[i] = benefit of adding an ith ambulance to cover single demand, calculated from busyFraction
	
	# arrays for recycling:
	stationNumIdleAmbs::Vector{Int} # stationNumIdleAmbs[i] = number of idle ambulances assigned to station i
	stationMarginalCoverages::Vector{Float} # stationMarginalCoverages[i] gives extra coverage provided from placing newly idle ambulance at station i
	# pointSetsCoverCounts::Vector{Vector{Int}} # pointSetsCoverCounts[i][j] = number of idle ambulances covering node set j, for demand.pointsCoverageModes i
	
	DmexclpData() = new(0.0, Dict(),
		[],
		[], [])
end

type PriorityListData <: MoveUpDataType
	# parameters:
	priorityList::Vector{Int} # priorityList[i] gives station index that the ith free ambulance should be moved to
	
	# arrays for recycling:
	stationNumIdleAmbs::Vector{Int} # number of idle ambulances assigned to each station
	
	PriorityListData() = new([],
		[])
end

type ZhangIpData <: MoveUpDataType
	# parameters:
	marginalBenefits::Vector{Vector{Float}} # marginalBenefits[i][j] = benefit of adding a jth ambulance to station i
	stationCapacities::Vector{Int} # stationCapacities[i] is the number of ambulances that station i can hold on completion of move up, should be <= stations[i].capacity
	travelTimeCost::Float # travel time cost multiplier
	onRoadMoveUpDiscountFactor::Float # discount of travel cost of move up of ambulance on-road and with "regret" travel time <= regretTravelTimeThreshold
	regretTravelTimeThreshold::Float
	expectedHospitalTransferDuration::Float
	
	stationSlots::Vector{Int}
	benefitSlots::Vector{Float}
	marginalBenefitsDecreasing::Bool # true if benefit of adding ambulance j to a station is < benefit of adding ambulance j-1, for all stations
	stationSlotsOrderPairs::Array{Int,2} # stationSlotsOrderConstraintPairs[i,1:2] gives two stationSlots indices, first should be filled (with ambulance) before second
	
	ZhangIpData() = new([], [], 1.0, 1.0, nullTime, nullTime,
		[], [], false, Array{Int,2}(0,0))
end

type Temp0Data <: MoveUpDataType
	# parameters:
	busyFraction::Float # ambulance busy fraction - should remove this, make marginalBenefit a parameter
	travelTimeCost::Float # travel time cost multiplier
	maxIdleAmbTravelTime::Float # max travel time for idle ambulances. 0.021 (days) is about 30 minutes
	maxNumNearestStations::Int # number of nearest stations to consider for each ambulance (may include ambulance's station)
	
	marginalBenefit::Vector{Float} # marginalBenefit[i] = benefit of adding an ith ambulance to a station
	
	Temp0Data() = new(0.0, 0.0, Inf, 0,
		[])
end

type Temp1Data <: MoveUpDataType
	# parameters:
	benefit::Array{Vector{Float},2} # benefit[i1,i2][k] = benefit from having k ambulances collectively at stations i1 and i2
	busyFraction::Float # ambulance busy fraction - should remove this, make marginalBenefit a parameter
	stationPairs::Vector{Vector{Int}} # stationPairs[i] gives ith station pair, which is a pair of station indices
	travelTimeCost::Float # travel time cost multiplier
	maxIdleAmbTravelTime::Float # max travel time for idle ambulances
	maxNumNearestStations::Int # number of nearest stations to consider for each ambulance (may include ambulance's station)
	
	marginalBenefit::Array{Vector{Float},2} # marginal benefit values from ambulance to station allocations, calculated from 'benefit'
	
	Temp1Data() = new(Array{Vector{Float},2}(0,0), 0.0, Vector{Vector{Int}}(0), 0.0, Inf, 0,
		Array{Vector{Float},2}(0,0))
end

type Temp2Data <: MoveUpDataType
	# parameters:
	benefit::Array{Array{Float,2},2} # benefit[i1,i2][k1,k2] = benefit from having k1 and k2 ambulances at stations i1 and i2, respectively
	busyFraction::Float # ambulance busy fraction - should remove this, make marginalBenefit a parameter
	stationPairs::Vector{Vector{Int}} # stationPairs[i] gives ith station pair, which is a pair of station indices
	travelTimeCost::Float # travel time cost multiplier
	maxIdleAmbTravelTime::Float # max travel time for idle ambulances
	maxNumNearestStations::Int # number of nearest stations to consider for each ambulance (may include ambulance's station)
	
	marginalBenefit::Array{Array{Float,2},2} # marginal benefit values from ambulance to station allocations, calculated from 'benefit'
	
	Temp2Data() = new(Array{Array{Float,2},2}(0,0), 0.0, Vector{Vector{Int}}(0), 0.0, Inf, 0,
		Array{Array{Float,2},2}(0,0))
end

type MoveUpData
	# parameters:
	useMoveUp::Bool
	moveUpModule::MoveUpModule # indicates move up module to be used
	
	# move up data types:
	compTableData::CompTableData
	dmexclpData::DmexclpData
	priorityListData::PriorityListData
	zhangIpData::ZhangIpData
	temp0Data::Temp0Data
	temp1Data::Temp1Data
	temp2Data::Temp2Data
	
	MoveUpData() = new(false, nullMoveUpModule,
		CompTableData(), DmexclpData(), PriorityListData(), ZhangIpData(), Temp0Data(), Temp1Data(), Temp2Data())
end

type File
	name::String
	path::String # includes name
	iostream::IOStream
	checksum::UInt
	
	# File() = new()
	File() = new("", "", IOStream(""), 0)
end

type Resimulation
	# parameters:
	use::Bool # true if resimulating (will follow event trace), false otherwise
	timeTolerance::Float
	
	events::Vector{Event}
	eventsChildren::Vector{Vector{Event}} # eventsChildren[i] gives events that are children of event i
	prevEventIndex::Int # index of previous event in events field
	
	Resimulation() = new(false, 0.0,
		[], [], nullIndex)
end

type Simulation
	startTime::Float
	time::Float # time of most recent event, or time of recent animation frame if animating
	endTime::Float # calculated after simulating
	
	# world:
	net::Network
	travel::Travel
	map::Map
	grid::Grid
	
	ambulances::Vector{Ambulance}
	calls::Vector{Call}
	hospitals::Vector{Hospital}
	stations::Vector{Station}
	
	# shorthand:
	numAmbs::Int # length(ambulances)
	numCalls::Int # length(calls)
	numHospitals::Int # length(hospitals)
	numStations::Int # length(stations)
	
	eventList::Vector{Event} # events to occur now or in future
	eventIndex::Int # index of event in events that have occurred
	queuedCallList::Vector{Call} # keep track of queued calls. Calls can be queued after call arrivalTime + dispatchDelay
	
	resim::Resimulation
	
	# decision logic
	addCallToQueue!::Function
	findAmbToDispatch!::Function
	moveUpData::MoveUpData
	
	# demand
	demand::Demand
	demandCoverage::DemandCoverage
	
	responseTravelPriorities::Dict{Priority,Priority} # responseTravelPriorities[p] gives the travel priority for responding to call of priority p
	targetResponseTimes::Vector{Float} # targetResponseTimes[Int(priority)] gives maximum desired response time for call of given priority
	
	# for animation:
	currentCalls::Set{Call} # all calls between arrival and service finish at current time
	previousCalls::Set{Call} # calls in currentCalls for previous frame
	
	# files/folders:
	inputPath::String
	outputPath::String
	inputFiles::Dict{String,File} # given input file name (e.g. "ambulances"), returns file information
	outputFiles::Dict{String,File}
	eventsFileIO::IOStream # write simulation trace of events to this file
	
	writeOutput::Bool # true if outputFiles should be used to write output (false if animating)
	initialised::Bool # true if simulation has been initialised and so can be run, false otherwise
	used::Bool # true if simulation has started running (and so restarting would require copying from backup)
	complete::Bool # true if simulation has ended (no events remaining)
	animating::Bool # true if being used for animation, false otherwise
	
	backup::Simulation # copy of simulation, for restarts (does not include a backup of all fields in order to save on memory, see backupSim! function for missing fields)
	
	configRootElt::XMLElement
	
	Simulation() = new(nullTime, nullTime, nullTime,
		Network(), Travel(), Map(), Grid(),
		[], [], [], [],
		0, 0, 0, 0,
		[], 0, [],
		Resimulation(),
		nullFunction, nullFunction, MoveUpData(),
		Demand(), DemandCoverage(),
		Dict(), [],
		Set(), Set(),
		"", "", Dict(), Dict(), IOStream(""),
		false, false, false, false, false)
end
