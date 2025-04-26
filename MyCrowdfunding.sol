// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Crowdfunding is Ownable(msg.sender), ReentrancyGuard {
    enum ProjectStatus {
        Draft,
        Active,
        ReachedGoal,
        Completed,
        Failed,
        Refunded,
        PartiallyRefunded,
        Canceled
    }

    struct Project {
        uint256 projectID;
        string projectTitle;
        string projectDescription;
        address payable projectOwner;
        uint256 projectParticipationAmount;
        uint256 projectTotalFundingAmount;
        uint256 withdrawnAmount;
        uint256 fundingGoal;
        uint256 deadline;
        ProjectStatus status;
        bool exists; // Added an extra variable to check if the project exists
    }

    // Define a struct for contribution details
    struct Contribution {
        uint256 projectID;
        uint256 contributionAmount;
    }

    uint256 counter;

    mapping(uint256 => Project) projectListing;
    mapping(address => mapping(uint256 => uint256)) contributions;

    // Add a mapping to track contributors for each project
    mapping(uint256 => address[]) projectContributors;
    mapping(uint256 => mapping(address => bool)) isContributor;

    // Event which can be listened to from a web app or another contract to generate a notification to the project owner
    event ProjectCreated(
        uint256 projectID,
        address projectOwner,
        string projectTitle,
        string projectDescription,
        uint256 projectParticipationAmount,
        uint256 fundingGoal,
        uint256 deadline
    );
    event ProjectStatusChanged(uint256 projectID, ProjectStatus newStatus);
    event ContributionMade(
        uint256 projectID,
        address contributor,
        uint256 amount
    );
    event FundsWithdrawn(
        uint256 projectID,
        address projectOwner,
        uint256 amount
    );
    event RefundIssued(uint256 projectID);
    event RefundProcessed(
        uint256 projectID,
        address contributor,
        uint256 amount
    );
    event RefundFailed(
        uint256 projectID,
        address contributor,
        uint256 amount,
        string reason
    );

    constructor() {
        counter = 0;
    }

    modifier onlyProjectOwner(uint256 _projectID) {
        require(
            msg.sender == projectListing[_projectID].projectOwner,
            "Only project owner can call this function"
        );
        _;
    }

    modifier moreThanOrEqualProjectParticipationAmount(uint256 _projectID) {
        // Used openzeppelin string functions to concat uint256 to a string
        string memory errorMessage = string.concat(
            "Participation Amount should be greater than or equal ",
            Strings.toString(
                projectListing[_projectID].projectParticipationAmount
            )
        );
        require(
            msg.value >= projectListing[_projectID].projectParticipationAmount,
            errorMessage
        );
        _;
    }

    modifier projectExists(uint256 _projectID) {
        require(projectListing[_projectID].exists, "Project ID doesn't exist");
        _;
    }

    modifier fundsAvailableToWithdraw(uint256 _projectID) {
        uint256 availableToWithdraw = projectListing[_projectID]
            .projectTotalFundingAmount -
            projectListing[_projectID].withdrawnAmount;
        require(availableToWithdraw > 0, "No funds available to withdraw");
        _;
    }

    modifier projectsAvailable() {
        require(counter > 0, "There are no projects available yet");
        _;
    }

    modifier projectActive(uint256 _projectID) {
        require(
            projectListing[_projectID].status == ProjectStatus.Active ||
                projectListing[_projectID].status == ProjectStatus.ReachedGoal,
            "Project is not active"
        );
        _;
    }

    modifier projectDeadlinePassed(uint256 _projectID) {
        require(
            block.timestamp >= projectListing[_projectID].deadline,
            "Project funding period is still active"
        );
        _;
    }

    modifier canWithdrawFunds(uint256 _projectID) {
        require(
            projectListing[_projectID].status == ProjectStatus.ReachedGoal ||
                projectListing[_projectID].status == ProjectStatus.Completed,
            "Project has not met its funding goal"
        );
        _;
    }

    modifier canRefund(uint256 _projectID) {
        require(
            projectListing[_projectID].status == ProjectStatus.Failed ||
                projectListing[_projectID].status == ProjectStatus.Canceled,
            "Project does not qualify for refunds"
        );
        _;
    }

    function createProject(
        string calldata _projectTitle,
        string calldata _projectDescription,
        uint256 _projectParticipationAmount,
        uint256 _fundingGoal,
        uint256 _durationInDays
    ) public {
        require(
            bytes(_projectTitle).length > 0,
            "Project title cannot be empty"
        );
        require(
            bytes(_projectDescription).length > 0,
            "Project description cannot be empty"
        );
        require(
            _projectParticipationAmount > 0,
            "Participation amount must be greater than 0"
        );
        require(_fundingGoal > 0, "Funding goal must be greater than 0");

        counter++;
        uint256 projectDeadline = block.timestamp + (_durationInDays * 1 days);

        projectListing[counter] = Project(
            counter,
            _projectTitle,
            _projectDescription,
            payable(msg.sender),
            _projectParticipationAmount,
            0,
            0,
            _fundingGoal,
            projectDeadline,
            ProjectStatus.Draft,
            true
        );

        emit ProjectCreated(
            counter,
            msg.sender,
            _projectTitle,
            _fundingGoal,
            projectDeadline
        );
    }

    function activateProject(
        uint256 _projectID
    ) public projectExists(_projectID) onlyProjectOwner(_projectID) {
        require(
            projectListing[_projectID].status == ProjectStatus.Draft,
            "Project must be in Draft status to activate"
        );
        projectListing[_projectID].status = ProjectStatus.Active;

        emit ProjectStatusChanged(_projectID, ProjectStatus.Active);
    }

    function participateToProject(
        uint256 _projectID
    )
        public
        payable
        projectExists(_projectID)
        projectActive(_projectID)
        moreThanOrEqualProjectParticipationAmount(_projectID)
    {
        projectListing[_projectID].projectTotalFundingAmount += msg.value;
        contributions[msg.sender][_projectID] += msg.value;

        // Add contributor to the project's contributors list if first contribution
        if (!isContributor[_projectID][msg.sender]) {
            projectContributors[_projectID].push(msg.sender);
            isContributor[_projectID][msg.sender] = true;
        }

        // Check if the funding goal is reached
        if (
            projectListing[_projectID].status != ProjectStatus.ReachedGoal &&
            projectListing[_projectID].projectTotalFundingAmount >=
            projectListing[_projectID].fundingGoal
        ) {
            projectListing[_projectID].status = ProjectStatus.ReachedGoal;
            emit ProjectStatusChanged(_projectID, ProjectStatus.ReachedGoal);
        }

        emit ContributionMade(_projectID, msg.sender, msg.value);
    }

    function getProjectDetails(
        uint256 _projectID
    )
        public
        view
        projectExists(_projectID)
        returns (
            string memory ProjectTitle,
            string memory ProjectDescription,
            address ProjectOwner,
            uint256 ParticipationAmount,
            uint256 ProjectTotalFundingAmount,
            uint256 FundingGoal,
            uint256 Deadline,
            ProjectStatus Status
        )
    {
        Project memory project = projectListing[_projectID];
        return (
            project.projectTitle,
            project.projectDescription,
            project.projectOwner,
            project.projectParticipationAmount,
            project.projectTotalFundingAmount,
            project.fundingGoal,
            project.deadline,
            project.status
        );
    }

    function retrieveContributions(
        address _address,
        uint256 _projectID
    )
        public
        view
        onlyOwner
        projectExists(_projectID)
        returns (uint256 Contribution)
    {
        return (contributions[_address][_projectID]);
    }

    function retrieveMyContributions(
        uint256 _projectID
    ) public view projectExists(_projectID) returns (uint256 Contribution) {
        return (contributions[msg.sender][_projectID]);
    }

    function retrieveAvailableFundsToWithdraw(
        uint256 _projectID
    )
        public
        view
        projectExists(_projectID)
        onlyProjectOwner(_projectID)
        returns (uint256 AvailableFunds)
    {
        return (projectListing[_projectID].projectTotalFundingAmount -
            projectListing[_projectID].withdrawnAmount);
    }

    function withdrawFunds(
        uint256 _projectID
    )
        public
        nonReentrant
        projectExists(_projectID)
        onlyProjectOwner(_projectID)
        fundsAvailableToWithdraw(_projectID)
        canWithdrawFunds(_projectID)
    {
        uint256 availableToWithdraw = projectListing[_projectID]
            .projectTotalFundingAmount -
            projectListing[_projectID].withdrawnAmount;
        projectListing[_projectID].withdrawnAmount += availableToWithdraw;

        // Using call instead of transfer for better error handling and gas flexibility
        (bool success, ) = payable(msg.sender).call{value: availableToWithdraw}(
            ""
        );
        require(success, "Transfer failed");

        emit FundsWithdrawn(_projectID, msg.sender, availableToWithdraw);
    }

    function listAllProjects()
        public
        view
        projectsAvailable
        returns (Project[] memory Projects)
    {
        Project[] memory allProjects = new Project[](counter);
        for (uint256 i = 1; i <= counter; i++) {
            allProjects[i - 1] = projectListing[i];
        }
        return allProjects;
    }

    // Get all projects a user has contributed to
    function getMyContributedProjects()
        public
        view
        returns (Contribution[] memory)
    {
        uint256 count = 0;
        for (uint256 i = 1; i <= counter; i++) {
            if (contributions[msg.sender][i] > 0) {
                count++;
            }
        }

        Contribution[] memory userContributions = new Contribution[](count);

        uint256 index = 0;
        for (uint256 i = 1; i <= counter; i++) {
            if (contributions[msg.sender][i] > 0) {
                userContributions[index] = Contribution(
                    i,
                    contributions[msg.sender][i]
                );
                index++;
            }
        }

        return userContributions;
    }

    // Function to get the number of projects
    function getNumberOfProjects() public view returns (uint256 Count) {
        return counter;
    }

    function changeProjectStatus(
        uint256 _projectID,
        ProjectStatus _newStatus
    ) public onlyOwner projectExists(_projectID) {
        projectListing[_projectID].status = _newStatus;
        emit ProjectStatusChanged(_projectID, _newStatus);
    }

    function processProjectRefunds(
        uint256 _projectID
    )
        public
        nonReentrant
        onlyOwner
        projectExists(_projectID)
        canRefund(_projectID)
    {
        address[] memory contributors = getProjectContributors(_projectID);
        require(contributors.length > 0, "No contributors for this project");
        require(
            projectListing[_projectID].status != ProjectStatus.Refunded,
            "Project is already refunded"
        );

        uint256 successfulRefunds = 0;
        uint256 failedRefunds = 0;

        for (uint256 i = 0; i < contributors.length; i++) {
            address contributor = contributors[i];
            uint256 contributionAmount = contributions[contributor][_projectID];

            if (contributionAmount == 0) {
                // Skip if no contribution
                continue;
            }

            // Reset contribution before transfer to prevent reentrancy
            contributions[contributor][_projectID] = 0;

            // Attempt to send refund
            (bool success, ) = payable(contributor).call{
                value: contributionAmount
            }("");

            if (success) {
                // Refund successful
                successfulRefunds++;
                emit RefundProcessed(
                    _projectID,
                    contributor,
                    contributionAmount
                );
            } else {
                // Refund failed, restore the contribution record
                contributions[contributor][_projectID] = contributionAmount;
                failedRefunds++;
                emit RefundFailed(
                    _projectID,
                    contributor,
                    contributionAmount,
                    "Transfer failed"
                );
            }
        }

        // Update project status
        if (successfulRefunds > 0) {
            if (failedRefunds == 0) {
                projectListing[_projectID].status = ProjectStatus.Refunded;
                emit ProjectStatusChanged(_projectID, ProjectStatus.Refunded);
            } else if (
                projectListing[_projectID].status !=
                ProjectStatus.PartiallyRefunded
            ) {
                projectListing[_projectID].status = ProjectStatus
                    .PartiallyRefunded;
                emit ProjectStatusChanged(
                    _projectID,
                    ProjectStatus.PartiallyRefunded
                );
            }
        }

        emit RefundIssued(_projectID);
    }

    // Function to update project details, only allowed before any contributions
    function updateProjectDetails(
        uint256 _projectID,
        string calldata _projectTitle,
        string calldata _projectDescription,
        uint256 _projectParticipationAmount,
        uint256 _fundingGoal,
        uint256 _durationInDays
    ) public projectExists(_projectID) onlyProjectOwner(_projectID) {
        Project storage project = projectListing[_projectID];

        // Only allow updates if no contributions have been made yet
        require(
            project.projectTotalFundingAmount == 0,
            "Cannot update project after contributions have been made"
        );

        // Validate inputs
        require(
            bytes(_projectTitle).length > 0,
            "Project title cannot be empty"
        );
        require(
            bytes(_projectDescription).length > 0,
            "Project description cannot be empty"
        );
        require(
            _projectParticipationAmount > 0,
            "Participation amount must be greater than 0"
        );
        require(_fundingGoal > 0, "Funding goal must be greater than 0");
        require(
            _durationInDays > 0 && _durationInDays <= 365,
            "Duration must be between 1 and 365 days"
        );

        // Update project details
        project.projectTitle = _projectTitle;
        project.projectDescription = _projectDescription;
        project.projectParticipationAmount = _projectParticipationAmount;
        project.fundingGoal = _fundingGoal;
        project.deadline = block.timestamp + (_durationInDays * 1 days);
    }

    // Allow the contract owner to batch update expired projects
    function batchUpdateExpiredProjects() public onlyOwner {
        uint256[] memory projectIDs = getProjectsNeedingStatusUpdate();
        for (uint256 i = 0; i < projectIDs.length; i++) {
            uint256 projectID = projectIDs[i];
            if (projectListing[projectID].status == ProjectStatus.ReachedGoal) {
                projectListing[projectID].status = ProjectStatus.Completed;
            } else {
                projectListing[projectID].status = ProjectStatus.Failed;
            }
            emit ProjectStatusChanged(
                projectID,
                projectListing[projectID].status
            );
        }
    }

    // Get all projects needing status updates
    function getProjectsNeedingStatusUpdate()
        private
        view
        returns (uint256[] memory ProjectsIDs)
    {
        uint256 count = 0;

        // First count how many projects need updates
        for (uint256 i = 1; i <= counter; i++) {
            if (
                projectListing[i].exists &&
                (projectListing[i].status == ProjectStatus.Active ||
                    projectListing[i].status == ProjectStatus.ReachedGoal) &&
                block.timestamp >= projectListing[i].deadline
            ) {
                count++;
            }
        }

        // Then populate the array
        uint256[] memory projectIDs = new uint256[](count);
        uint256 index = 0;

        for (uint256 i = 1; i <= counter; i++) {
            if (
                projectListing[i].exists &&
                (projectListing[i].status == ProjectStatus.Active ||
                    projectListing[i].status == ProjectStatus.ReachedGoal) &&
                block.timestamp >= projectListing[i].deadline
            ) {
                projectIDs[index] = i;
                index++;
            }
        }

        return projectIDs;
    }

    // Get projects by owner
    function getProjectsByOwner(
        address _owner
    ) public view returns (uint256[] memory ProjectsIDs) {
        uint256 count = 0;

        // First count projects owned by this address
        for (uint256 i = 1; i <= counter; i++) {
            if (
                projectListing[i].exists &&
                projectListing[i].projectOwner == _owner
            ) {
                count++;
            }
        }

        // Then populate the array
        uint256[] memory projectIDs = new uint256[](count);
        uint256 index = 0;

        for (uint256 i = 1; i <= counter; i++) {
            if (
                projectListing[i].exists &&
                projectListing[i].projectOwner == _owner
            ) {
                projectIDs[index] = i;
                index++;
            }
        }

        return projectIDs;
    }

    // Get all projects with a specific status
    function getProjectsByStatus(
        ProjectStatus _status
    ) public view returns (uint256[] memory ProjectsIDs) {
        uint256 count = 0;

        // First count projects with this status
        for (uint256 i = 1; i <= counter; i++) {
            if (
                projectListing[i].exists && projectListing[i].status == _status
            ) {
                count++;
            }
        }

        // Then populate the array
        uint256[] memory projectIDs = new uint256[](count);
        uint256 index = 0;

        for (uint256 i = 1; i <= counter; i++) {
            if (
                projectListing[i].exists && projectListing[i].status == _status
            ) {
                projectIDs[index] = i;
                index++;
            }
        }

        return projectIDs;
    }

    // Get projects closing soon (within the next 'days' days)
    function getProjectsClosingSoon(
        uint256 _days
    ) public view returns (uint256[] memory ProjectsIDs) {
        uint256 count = 0;
        uint256 futureTimestamp = block.timestamp + (_days * 1 days);

        // First count eligible projects
        for (uint256 i = 1; i <= counter; i++) {
            if (
                projectListing[i].exists &&
                (projectListing[i].status == ProjectStatus.Active ||
                    projectListing[i].status == ProjectStatus.ReachedGoal) &&
                projectListing[i].deadline > block.timestamp &&
                projectListing[i].deadline <= futureTimestamp
            ) {
                count++;
            }
        }

        // Then populate the array
        uint256[] memory projectIDs = new uint256[](count);
        uint256 index = 0;

        for (uint256 i = 1; i <= counter; i++) {
            if (
                projectListing[i].exists &&
                projectListing[i].status == ProjectStatus.Active &&
                projectListing[i].deadline > block.timestamp &&
                projectListing[i].deadline <= futureTimestamp
            ) {
                projectIDs[index] = i;
                index++;
            }
        }

        return projectIDs;
    }

    // Get all contributors for a specific project
    function getProjectContributors(
        uint256 _projectID
    )
        public
        view
        onlyOwner
        projectExists(_projectID)
        returns (address[] memory)
    {
        return projectContributors[_projectID];
    }
}
