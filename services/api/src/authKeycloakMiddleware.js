const Keycloak = require('keycloak-connect');
const Setup = require('keycloak-connect/middleware/setup');
const GrantAttacher = require('keycloak-connect/middleware/grant-attacher');
const R = require('ramda');
const { getPermissionsForUser } = require('./util/auth');

const lagoonRoutes =
  (process.env.LAGOON_ROUTES && process.env.LAGOON_ROUTES.split(',')) || [];

const lagoonKeycloakRoute = lagoonRoutes.find(routes =>
  routes.includes('keycloak-'),
);

const keycloak = new Keycloak(
  {},
  {
    realm: 'lagoon',
    serverUrl:
      lagoonKeycloakRoute ? `${lagoonKeycloakRoute}/auth` : 'http://docker.for.mac.localhost:8088/auth',
    clientId: 'lagoon-ui',
    publicClient: true,
    bearerOnly: true,
  },
);

// Override default of returning a 403
keycloak.accessDenied = (req, res, next) => {
  console.log('keycloak.accessDenied');
  next();
};

const authWithKeycloak = async (req, res, next) => {
  if (!req.kauth.grant) {
    next();
    return;
  }

  const ctx = req.app.get('context');
  const dao = ctx.dao;

  try {
    // Admins have full access and don't need a list of permissions
    if (R.contains('admin', req.kauth.grant.access_token.content.realm_access.roles)) {
      req.credentials = {
        role: 'admin',
        permissions: {},
      };
    } else {
      const {
        content: {
          lagoon: { user_id: userId },
        },
      } = req.kauth.grant.access_token;

      const permissions = await getPermissionsForUser(dao, userId);

      if (R.isEmpty(permissions)) {
        res.status(401).send({
          errors: [
            {
              message: `Unauthorized - No permissions for user id ${userId}`,
            },
          ],
        });
        return;
      }

      req.credentials = {
        role: 'none',
        userId,
        // Read and write permissions
        permissions,
      };
    }
    next();
  } catch (e) {
    res.status(403).send({
      errors: [
        {
          message: `Forbidden - Invalid Keycloak Token: ${e.message}`,
        },
      ],
    });
  }
};

const authKeycloakMiddleware = () => [
  Setup,
  GrantAttacher(keycloak),
  authWithKeycloak,
];

module.exports = {
  authKeycloakMiddleware,
};